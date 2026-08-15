package ui

import "core:strconv"
import "../cfg"
import "../cs2"
import "../renderer"

BOX_ASPECT           :: 2.4
HEAD_HEIGHT_FALLBACK :: 65
HEAD_Z_OFFSET        :: 7
MAX_HEALTH           :: 100
HEALTH_BAR_WIDTH     :: 3
HEALTH_BAR_PAD       :: 5

to_color :: proc (c: cfg.Color) -> renderer.Color {
	return renderer.Color {r = c.r, g = c.g, b = c.b, a = c.a}
}

fixed_string :: proc (buf: ^[128]u8) -> string {
	n := 0
	for n < len(buf) && buf[n] != 0 {
		n += 1
	}
	return string(buf[:n])
}

clip_runes :: proc (s: string, max_runes: int) -> string {
	count := 0
	for _, i in s {
		if count >= max_runes {
			return s[:i]
		}
		count += 1
	}
	return s
}

project :: proc (world: ^cs2.World, pos: cs2.Vec3, screen: [2]f32) -> (cs2.Vec2, bool) {
	return cs2.world_to_screen(
		world.view_matrix,
		pos,
		cs2.Vec2 {x = screen.x, y = screen.y},
	)
}

draw_esp :: proc (world: ^cs2.World, screen: [2]f32) {
	if !cfg.settings.esp.enabled {
		return
	}
	if world.local_index < 0 {
		return
	}

	local_team := world.local.team

	for i in 0 ..< world.player_count {
		player := &world.players[i]

		if !player.alive || player.local || player.team == local_team {
			continue
		}

		bottom, bottom_ok := project(world, player.pos, screen)

		head_pos := player.pos
		if player.bone_count > cs2.HEAD_BONE {
			head_pos = player.bones[cs2.HEAD_BONE]
			head_pos.z += HEAD_Z_OFFSET
		} else {
			head_pos.z += HEAD_HEIGHT_FALLBACK
		}

		top, top_ok := project(world, head_pos, screen)

		if !bottom_ok && !top_ok {
			continue
		}

		if !bottom_ok {
			bottom = cs2.Vec2 {x = top.x, y = screen.y}
		}

		if !top_ok {
			top = cs2.Vec2 {x = bottom.x, y = 0}
		}

		height := bottom.y - top.y
		if height <= 0 {
			continue
		}

		width := height / BOX_ASPECT
		x := top.x - width / 2
		y := top.y

		if cfg.settings.esp.box {
			renderer.draw_rect_outline(x,
				y, width, height, 1.5, to_color(cfg.settings.colors.box))
		}

		if cfg.settings.esp.health_bar || cfg.settings.esp.health_point {
			bar_x := x - HEALTH_BAR_PAD

			if cfg.settings.esp.health_bar {
				filled := height * clamp(f32(player.health) / MAX_HEALTH, 0, 1)
				renderer.draw_rect_filled(
					bar_x,
					y + height - filled,
					HEALTH_BAR_WIDTH,
					filled,
					to_color(cfg.settings.colors.health),
				)
				renderer.draw_rect_outline(
					bar_x,
					y,
					HEALTH_BAR_WIDTH,
					height,
					1,
					renderer.Color {0, 0, 0, 120},
				)
			}
	
			if cfg.settings.esp.health_point {
				buf: [8]u8
				hp := strconv.write_int(buf[:], i64(player.health), 10)
				hp_size := renderer.font_measure(&renderer.font, hp, esp_scale())
				mid := (renderer.font.ascent + renderer.font.descent) / 2
				renderer.draw_text(
					bar_x - 3 - hp_size.x,
					y + height/2 + mid*esp_scale(),
					hp,
					esp_scale(),
					to_color(cfg.settings.colors.text),
				)
			}
		}

		if cfg.settings.esp.skeleton {
			proj: [cs2.BONE_COUNT]cs2.Vec2
			ok:   [cs2.BONE_COUNT]bool

			for conn in cs2.BONE_CONNECTIONS {
				if player.bone_count <= conn[0] || player.bone_count <= conn[1] {
					continue
				}
				if !ok[conn[0]] {
					proj[conn[0]], ok[conn[0]] =
						project(world, player.bones[conn[0]], screen)
				}
				if !ok[conn[1]] {
					proj[conn[1]], ok[conn[1]] =
						project(world, player.bones[conn[1]], screen)
				}
				if ok[conn[0]] && ok[conn[1]] {
					renderer.draw_line(proj[conn[0]].x,
						proj[conn[0]].y, proj[conn[1]].x, proj[conn[1]].y,
						1.5, to_color(cfg.settings.colors.skeleton))
				}
			}

			if player.bone_count > cs2.HEAD_BONE {
				if !ok[cs2.HEAD_BONE] {
					proj[cs2.HEAD_BONE], ok[cs2.HEAD_BONE] =
						project(world, player.bones[cs2.HEAD_BONE], screen)
				}
				if ok[cs2.HEAD_BONE] {
					renderer.draw_circle_outline(
						proj[cs2.HEAD_BONE].x,
						proj[cs2.HEAD_BONE].y,
						width / 6,
						to_color(cfg.settings.colors.skeleton),
					)
				}
			}
		}

		if cfg.settings.esp.name {
			name := fixed_string(&player.name)
			if cfg.settings.display.name_max > 0 {
				name = clip_runes(name, cfg.settings.display.name_max)
			}
			size := renderer.font_measure(&renderer.font, name, esp_scale())
			renderer.draw_text(
				x + width / 2 - size.x / 2,
				y - 16 * esp_scale(),
				name,
				esp_scale(),
				to_color(cfg.settings.colors.text),
			)
		}

		if cfg.settings.esp.c4 && player.has_c4 {
			size := renderer.font_measure(&renderer.font, "C4", esp_scale())
			renderer.draw_text(
				x + width / 2 - size.x / 2,
				y - 32 * esp_scale(), "C4",
				esp_scale(), 
				to_color(cfg.settings.colors.c4),
			)
		}

		if (cfg.settings.esp.weapon || cfg.settings.esp.ammo) && player.weapon.valid {
			s := esp_scale()
			has_weapon := cfg.settings.esp.weapon
			has_ammo := cfg.settings.esp.ammo && player.weapon.ammo >= 0

			// "WEAPON | AMMO"
			line: [64]u8
			line_len := 0

			if has_weapon {
				wn := player.weapon.name
				copy(line[line_len:], wn)
				line_len += len(wn)
			}

			if has_weapon && has_ammo {
				copy(line[line_len:], " | ")
				line_len += 3
			}

			if has_ammo {
				ammo_str := strconv.write_int(line[line_len:], i64(player.weapon.ammo), 10)
				line_len += len(ammo_str)
			}

			text := string(line[:line_len])
			size := renderer.font_measure(&renderer.font, text, s)
			renderer.draw_text(x + width / 2 - size.x / 2,
				y + height + 16 * s, text, s, to_color(cfg.settings.colors.text))
		}

		// flags
		flag_x := x + width + 10
		flag_y := y

		if cfg.settings.esp.flashed && player.flashed {
			renderer.draw_text(flag_x,
				flag_y, "F", esp_scale(), to_color(cfg.settings.colors.text))
			flag_y += 14 * esp_scale()
		}

		if cfg.settings.esp.reloading && player.weapon.reloading {
			renderer.draw_text(flag_x,
				flag_y, "R", esp_scale(), to_color(cfg.settings.colors.text))
			flag_y += 14 * esp_scale()
		}

		if cfg.settings.esp.scoping && player.scoped {
			renderer.draw_text(flag_x,
				flag_y, "S", esp_scale(), to_color(cfg.settings.colors.text))
			flag_y += 14 * esp_scale()
		}

		if cfg.settings.esp.defusing && player.defusing {
			renderer.draw_text(flag_x,
				flag_y, "D", esp_scale(), to_color(cfg.settings.colors.text))
			flag_y += 14 * esp_scale()
		}
	}

	if cfg.settings.esp.c4 && world.bomb.planted {
		if p, ok := project(world, world.bomb.pos, screen); ok {
			renderer.draw_circle_outline(p.x, p.y, 6, to_color(cfg.settings.colors.c4))
			size := renderer.font_measure(&renderer.font, "C4", esp_scale())
			renderer.draw_text(
				p.x - size.x / 2,
				p.y - 16 * esp_scale(),
				"C4",
				esp_scale(),
				to_color(cfg.settings.colors.c4),
			)
		}
	}

	if cfg.settings.esp.spectators {
		draw_spectators(world)
	}
}

draw_spectators :: proc (world: ^cs2.World) {
	x := cfg.settings.esp.spectators_x
	y := cfg.settings.esp.spectators_y

	renderer.draw_text(x,
		y, "[Spectators]", esp_scale(), to_color(cfg.settings.colors.text))
	y += 16 * esp_scale()

	for i in 0 ..< world.player_count {
		player := &world.players[i]

		if player.pawn_handle == 0 {
			continue
		}
		if player.observer_target != u32(world.local.pawn_handle) {
			continue
		}

		renderer.draw_text(x,
			y, fixed_string(&player.name), esp_scale(), to_color(cfg.settings.colors.text))
		y += 14 * esp_scale()
	}
}
