package cs2

import "../remote"

// largest single read is the controller-pointer bulk:
// (MAX_CLIENTS * ENTITY_ENTRY_STRIDE = 64 * 0x70 = 7168)
// + pawn span (~0x1c7a - 0x0330)
// + 30-bone array (BONE_COUNT * 32 = 960).
// this will be enough.
READ_BUFFER_SIZE :: 16 * 1024
PROCESS_NAME     :: "cs2.exe"

Game :: struct {
	process:     remote.Process,
	client:      remote.Module_Info,
	offsets:     Offsets,
	plans:       Plans,
	read_buffer: [READ_BUFFER_SIZE]u8,
}

Plans :: struct {
	pawn:              remote.Layout_Plan,
	controller:        remote.Layout_Plan,
	weapon:            remote.Layout_Plan,
	scene_node:        remote.Layout_Plan,
	planted_c4:        remote.Layout_Plan,
	observer_services: remote.Layout_Plan,
	weapon_services:   remote.Layout_Plan,
}

game_init :: proc (game: ^Game) -> remote.Error {
	pid, err := remote.find_process(PROCESS_NAME)
	if err != remote.Error.None {
		return err
	}

	game.process.pid = pid
	if game.process.handle == nil {
		handle, hijack_err := remote.hijack_handle(pid)
		if hijack_err != remote.Error.None {
			return hijack_err
		}
		game.process.handle = handle
	}

	client, module_err := remote.find_module(pid, "client.dll")
	if module_err != remote.Error.None {
		return module_err
	}

	game.client = client

	offsets, find_err := find_offsets(game.process.handle, game.client)
	if find_err != remote.Error.None {
		return find_err
	}

	game.offsets = offsets

	game.plans.pawn = remote.build_copy_plan(Counter_Strike_Player_Pawn)
	game.plans.controller = remote.build_copy_plan(Base_Player_Controller)
	game.plans.weapon = remote.build_copy_plan(Weapon_State)
	game.plans.scene_node = remote.build_copy_plan(Game_Scene_Node)
	game.plans.planted_c4 = remote.build_copy_plan(Planted_C4)
	game.plans.observer_services = remote.build_copy_plan(Player_Observer_Services)
	game.plans.weapon_services = remote.build_copy_plan(Player_Weapon_Services)

	return remote.Error.None
}

game_destroy :: proc (game: ^Game) {
	remote.close_process(game.process.handle)
	remote.plan_destroy(game.plans.pawn)
	remote.plan_destroy(game.plans.controller)
	remote.plan_destroy(game.plans.weapon)
	remote.plan_destroy(game.plans.scene_node)
	remote.plan_destroy(game.plans.planted_c4)
	remote.plan_destroy(game.plans.observer_services)
	remote.plan_destroy(game.plans.weapon_services)
}

read_span :: proc (
	game: ^Game,
	base: uintptr,
	plan: remote.Layout_Plan,
	out: ^$T,
) -> bool {
	err := remote.read(
		game.process.handle,
		base + uintptr(plan.span.base_offset),
		raw_data(game.read_buffer[:]),
		uint(plan.span.total_bytes),
	)
	if err != remote.Error.None {
		return false
	}

	value, apply_err := remote.apply_copy_plan(
		game.read_buffer[:plan.span.total_bytes],
		plan,
		T,
	)
	if apply_err != remote.Error.None {
		return false
	}

	out^ = value
	return true
}

resolve_entity :: proc (
	game: ^Game,
	list_heads: [ENTITY_LIST_HEAD_COUNT]u64,
	handle: uintptr,
) -> (uintptr, bool) {
	index := (handle & ENTITY_HANDLE_MASK) >> ENTITY_HANDLE_INDEX_SHIFT
	if index >= ENTITY_LIST_HEAD_COUNT || list_heads[index] == 0 {
		return 0, false
	}

	ptr: uintptr
	err := remote.read(
		game.process.handle,
		uintptr(
			list_heads[index]) + ENTITY_ENTRY_STRIDE * (handle & ENTITY_HANDLE_INDEX_MASK
		),
		&ptr,
	)
	if err != remote.Error.None || ptr == 0 {
		return 0, false
	}

	return ptr, true
}

read_view_matrix :: proc (game: ^Game, world: ^World) -> bool {
	err := remote.read(
		game.process.handle,
		game.client.base + game.offsets.view_matrix,
		&world.view_matrix,
	)
	return err == remote.Error.None
}

read_list_heads :: proc (
	game: ^Game,
	entity_list_ptr: uintptr,
) -> ([ENTITY_LIST_HEAD_COUNT]u64, bool) {
	heads: [ENTITY_LIST_HEAD_COUNT]u64
	err := remote.read(
		game.process.handle,
		entity_list_ptr + ENTITY_LIST_HEADS_OFFSET,
		&heads,
		uint(ENTITY_LIST_HEAD_COUNT * size_of(u64)),
	)
	if err != remote.Error.None {
		return heads, false
	}

	return heads, true
}

read_max_clients :: proc (game: ^Game) -> int {
	global_vars: uintptr
	if remote.read(
		game.process.handle,
		game.client.base + game.offsets.global_vars,
		&global_vars,
	) != remote.Error.None || global_vars == 0 {
		return MAX_CLIENTS
	}

	max_clients_value: i32
	if remote.read(
		game.process.handle,
		global_vars + GLOBAL_VARS_MAX_CLIENTS_OFFSET,
		&max_clients_value,
	) != remote.Error.None || max_clients_value <= 0 {
		return MAX_CLIENTS
	}

	return int(clamp(max_clients_value, 1, MAX_CLIENTS))
}

read_controllers :: proc (
	game: ^Game,
	list_heads: [ENTITY_LIST_HEAD_COUNT]u64,
	max_clients: int,
) -> ([MAX_CLIENTS]uintptr, bool) {
	controllers: [MAX_CLIENTS]uintptr

	err := remote.read(
		game.process.handle,
		uintptr(list_heads[0]) + ENTITY_ENTRY_STRIDE,
		raw_data(game.read_buffer[:]),
		uint(max_clients * ENTITY_ENTRY_STRIDE),
	)
	if err != remote.Error.None {
		return controllers, false
	}

	for i in 0 ..< max_clients {
		controllers[i] = uintptr((^u64)(&game.read_buffer[i * ENTITY_ENTRY_STRIDE])^)
	}

	return controllers, true
}

read_bones :: proc (game: ^Game, scene_node_ptr: uintptr, player: ^Player) {
	node: Game_Scene_Node

	if !read_span(game, scene_node_ptr, game.plans.scene_node, &node) {
		return
	}
	if node.bone_array_ptr == 0 {
		return
	}

	bones: [BONE_COUNT]Bone
	err := remote.read(
		game.process.handle,
		node.bone_array_ptr,
		&bones,
		uint(size_of([BONE_COUNT]Bone)),
	)
	if err != remote.Error.None {
		return
	}

	for b in 0 ..< BONE_COUNT {
		player.bones[b] = Vec3 {
			x = bones[b].pos[0],
			y = bones[b].pos[1],
			z = bones[b].pos[2],
		}
	}
	player.bone_count = BONE_COUNT
}

read_weapon :: proc (
	game: ^Game,
	list_heads: [ENTITY_LIST_HEAD_COUNT]u64,
	weapon_services_ptr: uintptr,
	player: ^Player,
) {
	services: Player_Weapon_Services
	if !read_span(game, weapon_services_ptr, game.plans.weapon_services, &services) {
		return
	}

	active_weapon := services.active_weapon_handle
	if active_weapon == 0 {
		return
	}

	weapon_ptr, ok := resolve_entity(game, list_heads, active_weapon)
	if !ok {
		return
	}

	w: Weapon_State
	if !read_span(game, weapon_ptr, game.plans.weapon, &w) {
		return
	}

	player.weapon.valid = true
	player.weapon.item_index = w.attribute_manager.item.definition_index
	player.weapon.ammo = w.remaining_ammo
	player.weapon.name = weapon_name(w.attribute_manager.item.definition_index)
	player.weapon.reloading = w.is_reloading
}

read_controller :: proc (
	game: ^Game,
	list_heads: [ENTITY_LIST_HEAD_COUNT]u64,
	controller_ptr: uintptr,
	player: ^Player,
) -> bool {
	player^ = {}

	c: Base_Player_Controller
	if !read_span(game, controller_ptr, game.plans.controller, &c) {
		return false
	}
	if c.pawn_handle == 0 {
		return false
	}
	pawn_handle := c.pawn_handle

	pawn_ptr, ok := resolve_entity(game, list_heads, uintptr(pawn_handle))
	if !ok {
		return false
	}

	p: Counter_Strike_Player_Pawn
	if !read_span(game, pawn_ptr, game.plans.pawn, &p) {
		return false
	}

	player.name = c.player_name
	player.pawn_handle = uintptr(pawn_handle)
	player.team = p.team_num
	player.health = p.health
	player.pos = Vec3 {
		x = p.old_origin[0],
		y = p.old_origin[1],
		z = p.old_origin[2],
	}
	player.alive = p.health > 0
	player.local = c.is_local_player
	player.scoped = p.is_scoping
	player.defusing = p.is_defusing
	player.flashed = p.flash_alpha > 0
	player.observer_target = 0

	if p.observer_services_ptr != 0 {
		obs: Player_Observer_Services
		if read_span(game, p.observer_services_ptr, game.plans.observer_services, &obs) {
			player.observer_target = obs.observer_target
		}
	}

	if player.alive {
		if p.game_scene_node_ptr != 0 {
			read_bones(game, p.game_scene_node_ptr, player)
		}
		if p.weapon_services_ptr != 0 {
			read_weapon(game, list_heads, p.weapon_services_ptr, player)
		}
	}

	return true
}

read_bomb :: proc (game: ^Game, world: ^World) {
	handle := game.process.handle
	base := game.client.base

	planted_ptr: uintptr
	if remote.read(
		handle,
		base + game.offsets.planted_c4,
		&planted_ptr,
	) == remote.Error.None && planted_ptr != 0 {
		bc: Planted_C4
		if read_span(game, planted_ptr, game.plans.planted_c4, &bc) {
			world.bomb.planted = true
			if bc.game_scene_node_ptr != 0 {
				node: Game_Scene_Node
				if read_span(game, bc.game_scene_node_ptr, game.plans.scene_node, &node) {
					world.bomb.pos = Vec3 {
						x = node.absolute_origin[0],
						y = node.absolute_origin[1],
						z = node.absolute_origin[2],
					}
				}
			}
		}
	}

	slot: uintptr
	if remote.read(
		handle,
		base + game.offsets.weapon_c4,
		&slot,
	) == remote.Error.None && slot != 0 {
		ent: uintptr
		if remote.read(handle, slot, &ent) == remote.Error.None && ent != 0 {
			carrier_raw: i32
			if remote.read(
				handle,
				ent + C4_OWNER_OFFSET,
				&carrier_raw,
			) == remote.Error.None {
				world.bomb.carrier = uintptr(carrier_raw)
			}
		}
	}
}

game_tick :: proc (game: ^Game, world: ^World) {
	world.player_count = 0
	world.local_index = -1
	world.bomb = {}

	if !read_view_matrix(game, world) {
		world.valid = false
		return
	}

	entity_list_ptr: uintptr
	if remote.read(
		game.process.handle,
		game.client.base + game.offsets.entity_list,
		&entity_list_ptr,
	) != remote.Error.None || entity_list_ptr == 0 {
		world.valid = false
		return
	}

	list_heads, heads_ok := read_list_heads(game, entity_list_ptr)
	if !heads_ok {
		world.valid = false
		return
	}

	max_clients := read_max_clients(game)

	controllers, ctrl_ok := read_controllers(game, list_heads, max_clients)
	if !ctrl_ok {
		world.valid = false
		return
	}

	read_bomb(game, world)

	for i in 0 ..< max_clients {
		controller := controllers[i]
		if controller == 0 {
			continue
		}

		player := &world.players[world.player_count]
		if !read_controller(game, list_heads, uintptr(controller), player) {
			continue
		}

		player.has_c4 = world.bomb.carrier != 0 && player.pawn_handle == world.bomb.carrier

		if player.local {
			world.local = player^
			world.local_index = world.player_count
		}

		world.player_count += 1
		if world.player_count >= MAX_CLIENTS {
			break
		}
	}

	world.valid = true
}
