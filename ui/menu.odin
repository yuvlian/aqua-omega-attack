package ui

import "core:fmt"
import "core:strconv"
import "core:sys/windows"
import "core:time"
import "../cfg"
import "../renderer"

PANEL_W   :: 300
ROW_H     :: 26

// slider button
EDGE_GRAB :: 4

DEBOUNCE_MS :: 300

last_toggle_ms: u64
insert_was_down := false
start_time := time.now()

Widget_Ctx :: struct {
	measure: bool,
	mouse:   [2]f32,
	clicked: bool,
	held:    bool,
}

Color_Field :: enum {
	Box,
	Skeleton,
	Text,
	Text_Outline,
	Health,
	C4,
}

Edit_Field :: enum {
	None,
	Tick,
	Fps,
}

Menu :: struct {
	visible:        bool,
	panel_x:        f32,
	panel_y:        f32,
	drag_started:   bool,
	drag_prev:      [2]f32,
	selected_color: Color_Field,
	editing_field:  Edit_Field,
	edit_buffer:    [16]u8,
	edit_len:       int,
}

font_scale :: proc () -> f32 {
	s := cfg.settings.display.font_size
	if s < 0.25 {
		return 1
	}
	return s
}

esp_scale :: proc () -> f32 {
	s := cfg.settings.display.esp_font_size
	if s < 0.25 {
		return 1
	}
	return s
}

// returns the baseline y for text center
text_y :: proc (y: f32) -> f32 {
	mid := (renderer.font.ascent + renderer.font.descent) / 2
	return y + ROW_H / 2 + mid * font_scale()
}

draw_label :: proc (text: string, x, y: f32, size: f32, color: renderer.Color) {
	renderer.draw_text(x, y, text, size, color)
}

section_header :: proc (title: string, ctx: ^Widget_Ctx, y: f32, menu: ^Menu) -> f32 {
	if !ctx.measure {
		draw_label(title,
			menu.panel_x + 8, text_y(y), font_scale(), renderer.Color {135, 206, 235, 255})
	}
	return y + ROW_H
}

reset_button :: proc (ctx: ^Widget_Ctx, y: f32, menu: ^Menu) -> f32 {
	if !ctx.measure {
		row := [4]f32 {menu.panel_x, y, PANEL_W, ROW_H}
		if ctx.clicked && point_in_rect(ctx.mouse, row) {
			cfg.settings = cfg.default_config()
		}
		bx := menu.panel_x + 8
		by := y + 3
		bw := f32(PANEL_W - 16)
		bh := f32(ROW_H - 6)
		renderer.draw_rect_filled(bx, by, bw, bh, renderer.Color {70, 70, 85, 255})
		renderer.draw_rect_outline(bx, by, bw, bh, 1, renderer.Color {135, 206, 235, 255})
		text := "Reset Settings"
		size := renderer.font_measure(&renderer.font, text, font_scale())
		renderer.draw_text(
			bx + bw/2 - size.x/2,
			text_y(y),
			text,
			font_scale(),
			renderer.Color {255, 255, 255, 255},
		)
	}
	return y + ROW_H
}

tick_row :: proc (ctx: ^Widget_Ctx, y: f32, menu: ^Menu) -> f32 {
	y2 := number_box("Tick Millisecond", &cfg.settings.engine.tick_ms, .Tick, ctx, y, menu)
	if !ctx.measure {
		if cfg.settings.engine.tick_ms < 1 {
			cfg.settings.engine.tick_ms = 1
		}
	}
	return y2
}

fps_row :: proc (ctx: ^Widget_Ctx, y: f32, menu: ^Menu) -> f32 {
	y2 := number_box("FPS Limit", &cfg.settings.engine.fps_limit, .Fps, ctx, y, menu)
	return y2
}

checkbox :: proc (
	label: string,
	value: ^bool,
	ctx: ^Widget_Ctx,
	y: f32,
	menu: ^Menu,
) -> f32 {
	if !ctx.measure {
		row := [4]f32 {menu.panel_x, y, PANEL_W, ROW_H}

		if ctx.clicked && point_in_rect(ctx.mouse, row) {
			value^ = !value^
		}

		cx := menu.panel_x + 8 + 7
		cy := y + ROW_H / 2
		if value^ {
			renderer.draw_circle_outline(cx, cy, 6, renderer.Color {255, 255, 255, 255})
		} else {
			renderer.draw_circle_filled(cx, cy, 6, renderer.Color {255, 255, 255, 255})
		}

		draw_label(
			label,
			menu.panel_x + 28,
			text_y(y),
			font_scale(),
			renderer.Color {255, 255, 255, 255},
		)
	}

	return y + ROW_H
}

slider :: proc (
	label: string,
	value: ^f32,
	min, max: f32,
	ctx: ^Widget_Ctx,
	y: f32,
	menu: ^Menu,
) -> f32 {
	if !ctx.measure {
		s := font_scale()
		label_w := renderer.font_measure(&renderer.font, label, s).x
		num_x := menu.panel_x + 8 + label_w + 10

		buf: [16]u8
		num := fmt.bprintf(buf[:], "{}", value^)
		num_w := renderer.font_measure(&renderer.font, num, s).x

		track_x := num_x + num_w + 12
		track_w := menu.panel_x + PANEL_W - 8 - track_x
		if track_w < 0 {
			track_w = 0
		}
		frac := clamp((value^ - min) / (max - min), 0, 1)

		hit := [4]f32 {track_x, y, track_w, ROW_H}
		if (ctx.clicked || ctx.held) && track_w > 0 && point_in_rect(ctx.mouse, hit) {
			mx := ctx.mouse.x
			if mx <= track_x + EDGE_GRAB {
				value^ = min
			} else if mx >= track_x + track_w - EDGE_GRAB {
				value^ = max
			} else {
				value^ = clamp(min + (mx - track_x) / track_w * (max - min), min, max)
			}
			frac = clamp((value^ - min) / (max - min), 0, 1)
		}

		track_y := y + ROW_H / 2 - 2

		renderer.draw_rect_filled(track_x,
			track_y, track_w, 4, renderer.Color {64, 64, 64, 255})
	
		renderer.draw_rect_filled(track_x,
			track_y, track_w * frac, 4, renderer.Color {255, 255, 255, 255})

		renderer.draw_circle_outline(track_x + track_w * frac,
			y + ROW_H / 2, 4, renderer.Color {255, 255, 255, 255})

		draw_label(label,
			menu.panel_x + 8, text_y(y), s, renderer.Color {255, 255, 255, 255})

		draw_label(num, num_x, text_y(y), s, renderer.Color {200, 200, 200, 255})
	}

	return y + ROW_H
}

color_row :: proc (
	name: string,
	color: cfg.Color,
	field: Color_Field,
	ctx: ^Widget_Ctx,
	y: f32,
	menu: ^Menu,
) -> f32 {
	if !ctx.measure {
		row := [4]f32 {menu.panel_x, y, PANEL_W, ROW_H}

		if ctx.clicked && point_in_rect(ctx.mouse, row) {
			menu.selected_color = field
		}

		if menu.selected_color == field {
			renderer.draw_rect_outline(row.x,
				row.y, row.z, row.w, 1, renderer.Color {135, 206, 235, 255})
		}

		cy := y + ROW_H / 2
		renderer.draw_rect_filled(menu.panel_x + 8, cy - 6, 12, 12, to_color(color))
	
		renderer.draw_rect_outline(menu.panel_x + 8,
			cy - 6, 12, 12, 1, renderer.Color {255, 255, 255, 255})

		draw_label(
			name,
			menu.panel_x + 28,
			text_y(y),
			font_scale(),
			renderer.Color {255, 255, 255, 255},
		)
	}

	return y + ROW_H
}

number_box_float :: proc (
	label: string,
	value: ^f32,
	field: Edit_Field,
	ctx: ^Widget_Ctx,
	y: f32,
	menu: ^Menu,
) -> f32 {
	if !ctx.measure {
		box := [4]f32 {menu.panel_x + PANEL_W - 8 - 56, y + ROW_H / 2 - 8, 56, 16}
		draw_label(label,
			menu.panel_x + 8, text_y(y), font_scale(), renderer.Color {255, 255, 255, 255})

		if ctx.clicked {
			if point_in_rect(ctx.mouse, box) {
				if menu.editing_field != field {
					menu.editing_field = field
					menu.edit_len = len(fmt.bprintf(menu.edit_buffer[:], "{}", value^))
				}
			} else {
				commit_number_float(value, field, menu)
			}
		}

		if menu.editing_field == field {
			renderer.draw_rect_filled(box.x,
				box.y, box.z, box.w, renderer.Color {64, 64, 64, 255})

			text := string(menu.edit_buffer[:menu.edit_len])
			draw_label(
				text,
				box.x + 4,
				text_y(y),
				font_scale(),
				renderer.Color {255, 255, 255, 255},
			)

			for {
				ch, ok := renderer.char_poll()
				if !ok {
					break
				}
				if (ch >= '0' && ch <= '9' || ch == '.') && 
					menu.edit_len < len(menu.edit_buffer) - 1 {
					menu.edit_buffer[menu.edit_len] = u8(ch)
					menu.edit_len += 1
				}
			}

			if (int(windows.GetAsyncKeyState(windows.VK_BACK)) & 0x8000) != 0 && 
				menu.edit_len > 0 {
				menu.edit_len -= 1
			}
			if (int(windows.GetAsyncKeyState(windows.VK_RETURN)) & 0x8000) != 0 {
				commit_number_float(value, field, menu)
			}
		} else {
			renderer.draw_rect_outline(box.x,
				box.y, box.z, box.w, 1, renderer.Color {128, 128, 128, 255})
			buf: [16]u8
			text := fmt.bprintf(buf[:], "{}", value^)
			draw_label(
				text,
				box.x + 4,
				text_y(y),
				font_scale(),
				renderer.Color {200, 200, 200, 255},
			)
		}
	}

	return y + ROW_H
}

number_box_int :: proc (
	label: string,
	value: ^$T,
	field: Edit_Field,
	ctx: ^Widget_Ctx,
	y: f32,
	menu: ^Menu,
) -> f32 {
	if !ctx.measure {
		box := [4]f32 {menu.panel_x + PANEL_W - 8 - 56, y + ROW_H / 2 - 8, 56, 16}
		draw_label(label,
			menu.panel_x + 8, text_y(y), font_scale(), renderer.Color {255, 255, 255, 255})

		if ctx.clicked {
			if point_in_rect(ctx.mouse, box) {
				if menu.editing_field != field {
					menu.editing_field = field
					menu.edit_len = len(fmt.bprintf(menu.edit_buffer[:], "{}", value^))
				}
			} else {
				commit_number_int(value, field, menu)
			}
		}

		if menu.editing_field == field {
			renderer.draw_rect_filled(box.x,
				box.y, box.z, box.w, renderer.Color {64, 64, 64, 255})

			text := string(menu.edit_buffer[:menu.edit_len])
			draw_label(
				text,
				box.x + 4,
				text_y(y),
				font_scale(),
				renderer.Color {255, 255, 255, 255},
			)

			for {
				ch, ok := renderer.char_poll()
				if !ok {
					break
				}
				if ch >= '0' && ch <= '9' && menu.edit_len < len(menu.edit_buffer) - 1 {
					menu.edit_buffer[menu.edit_len] = u8(ch)
					menu.edit_len += 1
				}
			}

			if (int(windows.GetAsyncKeyState(windows.VK_BACK)) & 0x8000) != 0 && 
				menu.edit_len > 0 {
				menu.edit_len -= 1
			}
			if (int(windows.GetAsyncKeyState(windows.VK_RETURN)) & 0x8000) != 0 {
				commit_number_int(value, field, menu)
			}
		} else {
			renderer.draw_rect_outline(box.x,
				box.y, box.z, box.w, 1, renderer.Color {128, 128, 128, 255})
			buf: [16]u8
			text := fmt.bprintf(buf[:], "{}", value^)
			draw_label(
				text,
				box.x + 4,
				text_y(y),
				font_scale(),
				renderer.Color {200, 200, 200, 255},
			)
		}
	}

	return y + ROW_H
}

number_box :: proc {number_box_float, number_box_int}

point_in_rect :: proc (p: [2]f32, r: [4]f32) -> bool {
	return p.x >= r.x && p.x <= r.x + r.z && p.y >= r.y && p.y <= r.y + r.w
}

commit_number_float :: proc (value: ^f32, field: Edit_Field, menu: ^Menu) {
	if menu.editing_field == field {
		if menu.edit_len > 0 {
			if v, ok := strconv.parse_f32(string(menu.edit_buffer[:menu.edit_len])); ok {
				value^ = v
			}
		}
		menu.editing_field = .None
		menu.edit_len = 0
	}
}

commit_number_int :: proc (value: ^$T, field: Edit_Field, menu: ^Menu) {
	if menu.editing_field == field {
		if menu.edit_len > 0 {
			if v, ok := strconv.parse_i64(string(menu.edit_buffer[:menu.edit_len])); ok {
				value^ = T(v)
			}
		}
		menu.editing_field = .None
		menu.edit_len = 0
	}
}

selected_color_ptr :: proc (menu: ^Menu) -> ^cfg.Color {
	switch menu.selected_color {
	case .Box:          return &cfg.settings.colors.box
	case .Skeleton:     return &cfg.settings.colors.skeleton
	case .Text:         return &cfg.settings.colors.text
	case .Text_Outline: return &cfg.settings.colors.text_outline
	case .Health:       return &cfg.settings.colors.health
	case .C4:           return &cfg.settings.colors.c4
	case:				return &cfg.settings.colors.box
	}
}

layout_menu :: proc (ctx: ^Widget_Ctx, y0: f32, menu: ^Menu) -> f32 {
	y := y0
	y = section_header("ESP", ctx, y, menu)
	y = checkbox("Enabled", &cfg.settings.esp.enabled, ctx, y, menu)
	y = checkbox("Name", &cfg.settings.esp.name, ctx, y, menu)
	y = checkbox("Box", &cfg.settings.esp.box, ctx, y, menu)
	y = checkbox("Skeleton", &cfg.settings.esp.skeleton, ctx, y, menu)
	y = checkbox("Health Bar", &cfg.settings.esp.health_bar, ctx, y, menu)
	y = checkbox("Health Point", &cfg.settings.esp.health_point, ctx, y, menu)
	y = checkbox("Weapon", &cfg.settings.esp.weapon, ctx, y, menu)
	y = checkbox("Ammo", &cfg.settings.esp.ammo, ctx, y, menu)
	y = checkbox("C4", &cfg.settings.esp.c4, ctx, y, menu)
	y = checkbox("Spectators", &cfg.settings.esp.spectators, ctx, y, menu)
	y = slider("Spectators Y", &cfg.settings.esp.spectators_y, 0, 1500, ctx, y, menu)
	y = slider("Spectators X", &cfg.settings.esp.spectators_x, 0, 1500, ctx, y, menu)
	y = checkbox("Reloading", &cfg.settings.esp.reloading, ctx, y, menu)
	y = checkbox("Scoping", &cfg.settings.esp.scoping, ctx, y, menu)
	y = checkbox("Defusing", &cfg.settings.esp.defusing, ctx, y, menu)
	y = checkbox("Flashed", &cfg.settings.esp.flashed, ctx, y, menu)

	y = section_header("Display", ctx, y, menu)
	name_max := f32(cfg.settings.display.name_max)
	y = slider("Name Max Len", &name_max, 4, 32, ctx, y, menu)
	if !ctx.measure {
		cfg.settings.display.name_max = int(name_max)
	}
	y = slider("ESP Font Size",
			&cfg.settings.display.esp_font_size, 0.5, 1.4, ctx, y, menu)
	y = slider("Menu Font Size", &cfg.settings.display.font_size, 0.5, 1.4, ctx, y, menu)

	y = section_header("Colors", ctx, y, menu)
	y = color_row("Box", cfg.settings.colors.box, .Box, ctx, y, menu)
	y = color_row("Skeleton", cfg.settings.colors.skeleton, .Skeleton, ctx, y, menu)
	y = color_row("Text", cfg.settings.colors.text, .Text, ctx, y, menu)
	y = color_row("Text Outline",
			cfg.settings.colors.text_outline, .Text_Outline, ctx, y, menu)
	y = color_row("Health", cfg.settings.colors.health, .Health, ctx, y, menu)
	y = color_row("C4", cfg.settings.colors.c4, .C4, ctx, y, menu)

	sel := selected_color_ptr(menu)
	r := f32(sel.r)
	g := f32(sel.g)
	b := f32(sel.b)
	a := f32(sel.a)
	y = slider("R", &r, 0, 255, ctx, y, menu)
	y = slider("G", &g, 0, 255, ctx, y, menu)
	y = slider("B", &b, 0, 255, ctx, y, menu)
	y = slider("A", &a, 0, 255, ctx, y, menu)
	if !ctx.measure {
		sel.r = u8(r)
		sel.g = u8(g)
		sel.b = u8(b)
		sel.a = u8(a)
	}

	return y
}

draw_menu :: proc (menu: ^Menu, screen: [2]f32) {
	mouse := [2]f32 {renderer.mouse_x, renderer.mouse_y}
	clicked := renderer.left_pressed
	held := renderer.left_held

	measure_ctx := Widget_Ctx {measure = true}
	y := menu.panel_y + ROW_H
	y = tick_row(&measure_ctx, y, menu)
	y = fps_row(&measure_ctx, y, menu)
	y = reset_button(&measure_ctx, y, menu)
	y = layout_menu(&measure_ctx, y, menu)
	panel_h := y - menu.panel_y + ROW_H

	// make menu draggable on title bar
	header := [4]f32 {menu.panel_x, menu.panel_y, PANEL_W, 26}
	if !held {
		menu.drag_started = false
	} else if menu.drag_started || point_in_rect(mouse, header) {
		menu.drag_started = true
		menu.panel_x += mouse.x - menu.drag_prev.x
		menu.panel_y += mouse.y - menu.drag_prev.y
	}
	menu.drag_prev = mouse

	renderer.draw_rect_filled(menu.panel_x,
		menu.panel_y, PANEL_W, panel_h, renderer.Color {20, 20, 25, 230})
	renderer.draw_rect_outline(menu.panel_x,
		menu.panel_y, PANEL_W, panel_h, 1, renderer.Color {64, 64, 64, 255})

	draw_ctx := Widget_Ctx {measure = false, mouse = mouse, clicked = clicked, held = held}
	draw_label(
		cfg.WINDOW_TITLE,
		menu.panel_x + 8,
		text_y(menu.panel_y),
		font_scale(),
		renderer.Color {135, 206, 235, 255},
	)
	y = menu.panel_y + ROW_H
	y = tick_row(&draw_ctx, y, menu)
	y = fps_row(&draw_ctx, y, menu)
	y = reset_button(&draw_ctx, y, menu)
	y = layout_menu(&draw_ctx, y, menu)
	draw_label("INSERT toggles menu, closing saves.",
		menu.panel_x + 8, text_y(y), font_scale(), renderer.Color {128, 128, 128, 255})
}

menu_toggle :: proc (menu: ^Menu) -> bool {
	now_ms := u64(time.duration_milliseconds(time.since(start_time)))
	insert_down := (int(windows.GetAsyncKeyState(windows.VK_INSERT)) & 0x8000) != 0

	if insert_down && !insert_was_down && now_ms - last_toggle_ms >= DEBOUNCE_MS {
		last_toggle_ms = now_ms

		menu.visible = !menu.visible

		if menu.visible {
			renderer.window_set_clickthrough(false)
		} else {
			renderer.window_set_clickthrough(true)
			insert_was_down = insert_down
			return true
		}
	}

	insert_was_down = insert_down
	return false
}
