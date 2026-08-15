package cs2

Vec2 :: struct { x, y: f32 }
Vec3 :: struct { x, y, z: f32 }
Mat4 :: struct { m: [4][4]f32 }

world_to_screen :: proc (
	m: Mat4,
	pos: Vec3,
	screen: Vec2,
) -> (Vec2, bool) {
	view := m.m[3][0] * pos.x + m.m[3][1] * pos.y + m.m[3][2] * pos.z + m.m[3][3]

	if view <= 0.01 {
		return Vec2 {}, false
	}

	inv_view := 1 / view
	half_x := screen.x / 2
	half_y := screen.y / 2

	x_term := m.m[0][0] * pos.x + m.m[0][1] * pos.y + m.m[0][2] * pos.z + m.m[0][3]
	y_term := m.m[1][0] * pos.x + m.m[1][1] * pos.y + m.m[1][2] * pos.z + m.m[1][3]

	out := Vec2 {
		x = half_x + x_term * inv_view * half_x,
		y = half_y - y_term * inv_view * half_y,
	}

	return out, true
}
