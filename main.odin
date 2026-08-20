package main

import "core:fmt"
import "core:sys/windows"
import "core:time"
import "./cfg"
import "./cs2"
import "./remote"
import "./renderer"
import "./ui"

ATTACH_RETRY_INTERVAL  :: 2 * time.Second
// how often to check for game process
// rn we dont use SYNCHRONIZE & WaitForSingleObject cuz im lazy
LIVENESS_POLL_INTERVAL :: 500 * time.Millisecond

main :: proc () {
	cfg.load()

	monitor_w := windows.GetSystemMetrics(windows.SM_CXSCREEN)
	monitor_h := windows.GetSystemMetrics(windows.SM_CYSCREEN)

	hwnd, ok := renderer.window_create(cfg.WINDOW_TITLE,
		cfg.WINDOW_CLASS, int(monitor_w), int(monitor_h))

	if !ok {
		fmt.eprintln("failed to create overlay window")
		return
	}

	renderer.window_set_clickthrough(true)
	if !renderer.present_init(int(monitor_w), int(monitor_h)) {
		fmt.eprintln("failed to init presentation")
		return
	}

	game: cs2.Game
	attached := false
	game_pid: u32 = 0

	defer renderer.window_destroy(hwnd, cfg.WINDOW_CLASS)
	defer renderer.renderer_destroy(&renderer.ctx)
	defer cs2.game_destroy(&game)

	if !renderer.renderer_init(&renderer.ctx, int(monitor_w), int(monitor_h)) {
		fmt.eprintln("failed to initialize renderer")
		return
	}

	if !renderer.font_init(&renderer.font,
		&renderer.ctx, cfg.font_path(), renderer.PIXEL_HEIGHT) {
		fmt.eprintln("no usable font found; text disabled")
	}

	fmt.println("renderer initialized, entering loop")

	screen := [2]f32 {f32(monitor_w), f32(monitor_h)}
	world: cs2.World
	tick_timer := time.now()
	last_liveness := time.now()
	last_attach := time.now()
	menu: ui.Menu

	for !attached {
		if !renderer.window_pump_messages() {
			fmt.println("exiting: WM_QUIT")
			return
		}

		if time.since(last_attach) >= ATTACH_RETRY_INTERVAL {
			last_attach = time.now()
			if err := cs2.game_init(&game); err == remote.Error.None {
				attached = true
				game_pid = game.process.pid
				fmt.printf("attached to %s\n", cs2.PROCESS_NAME)
				break
			}
		}

		if ui.menu_toggle(&menu) {
			cfg.save()
		}

		draw_frame(hwnd, &menu, screen, game_pid, &world)
	}

	for {
		if !renderer.window_pump_messages() {
			fmt.println("exiting: WM_QUIT")
			break
		}

		if time.since(last_liveness) >= LIVENESS_POLL_INTERVAL {
			last_liveness = time.now()
			if !remote.process_exists(game_pid) {
				fmt.printf("%s closed, exiting\n", cs2.PROCESS_NAME)
				break
			}
		}

		if ui.menu_toggle(&menu) {
			cfg.save()
		}

		if time.since(tick_timer) >=
			time.Duration(cfg.settings.engine.tick_ms) * time.Millisecond {
			cs2.game_tick(&game, &world)
			tick_timer = time.now()
		}

		draw_frame(hwnd, &menu, screen, game_pid, &world)
	}
}

draw_frame :: proc (
	hwnd:       windows.HWND,
	menu:       ^ui.Menu,
	screen:     [2]f32,
	game_pid:   u32,
	world:      ^cs2.World,
) {
	renderer.input_poll(hwnd)

	renderer.renderer_set_text_outline(
		cfg.settings.colors.text_outline.r,
		cfg.settings.colors.text_outline.g,
		cfg.settings.colors.text_outline.b,
		cfg.settings.colors.text_outline.a,
	)

	frame_start := time.now()
	if !renderer.renderer_begin_frame(&renderer.ctx) {
		return
	}

	if world.valid && should_draw(game_pid, hwnd, menu.visible) {
		ui.draw_esp(world, screen)
	}
	if menu.visible {
		ui.draw_menu(menu, screen)
	}

	if !renderer.draw_flush(&renderer.ctx) {
		return
	}
	renderer.renderer_present(&renderer.ctx, hwnd)
	if cfg.settings.engine.fps_limit > 0 {
		target := time.Second / time.Duration(cfg.settings.engine.fps_limit)
		if elapsed := time.since(frame_start); elapsed < target {
			time.sleep(target - elapsed)
		}
	}
}

should_draw :: proc (game_pid: u32, hwnd: windows.HWND, menu_visible: bool) -> bool {
	if menu_visible {
		return true
	}
	foreground := windows.GetForegroundWindow()
	if foreground == hwnd {
		return true
	}
	return renderer.window_foreground_pid() == game_pid
}
