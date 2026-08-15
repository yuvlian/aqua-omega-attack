package cs2

// these r from signatures
Offsets :: struct {
	view_matrix: uintptr,
	entity_list: uintptr,
	global_vars: uintptr,
	planted_c4:  uintptr,
	weapon_c4:   uintptr,
}

// CEntityIdentity list layout
ENTITY_LIST_HEAD_COUNT    :: 64
ENTITY_LIST_HEADS_OFFSET  :: 0x10
ENTITY_ENTRY_STRIDE       :: 0x70
ENTITY_HANDLE_MASK        :: 0x7FFF
ENTITY_HANDLE_INDEX_SHIFT :: 9
ENTITY_HANDLE_INDEX_MASK  :: 0x1FF

// CGlobalVars
GLOBAL_VARS_MAX_CLIENTS_OFFSET :: 0x10

// m_hOwnerEntity inside weapon c4 slot entity
C4_OWNER_OFFSET :: 0x520

// CPlayer_ObserverServices {client}
Player_Observer_Services :: struct #packed {
	// m_hObserverTarget
	observer_target: u32 `0x004c`,
}

// C_AtributeContainer {client}
Attribute_Container :: struct #packed {
	// m_Item
	item: Econ_Item_View `0x0050`,
}

// CPlayer_WeaponServices {client}
Player_Weapon_Services :: struct #packed {
	// m_hActiveWeapon
	active_weapon_handle: uintptr `0x0060`,
}

// CGameSceneNode {client}
Game_Scene_Node :: struct #packed {
	// m_vecAbsOrigin
	absolute_origin: [3]f32 `0x00c8`,

	// undocumented? m_modelState (0x0140) + 0x80
	bone_array_ptr: uintptr `0x01C0`,
}

// Undocumented
Global_Vars :: struct #packed {
	map_name: [32]u8 `0x0180`,
}

// C_EconItemView {client}
Econ_Item_View :: struct #packed {
	// m_iItemDefinitionIndex
	definition_index: u16 `0x01BA`,
}

// C_PlantedC4 {client}
Planted_C4 :: struct #packed {
	// m_pGameSceneNode
	game_scene_node_ptr: uintptr `0x0330`,

	// m_nBombSite
	bomb_site: i32 `0x11A4`,
}

// C_CSPlayerPawn {client}
Counter_Strike_Player_Pawn :: struct #packed {
	// m_pGameSceneNode
	game_scene_node_ptr: uintptr `0x0330`,

	// m_iHealth
	health: i32 `0x034c`,

	// m_iTeamNum
	team_num: u8 `0x03e7`,

	// m_vecAbsVelocity
	velocity: [3]f32 `0x03f8`,

	// m_pWeaponServices
	weapon_services_ptr: uintptr `0x1208`,

	// m_pObserverServices
	observer_services_ptr: uintptr `0x1220`,

	// m_vOldOrigin
	old_origin: [3]f32 `0x13b8`,

	// m_flFlashOverlayAlpha
	flash_alpha: f32 `0x141c`,

	// m_bIsScoped
	is_scoping: bool `0x1c78`,

	// m_bIsDefusing
	is_defusing: bool `0x1c7a`,
}

// CBasePlayerController {client}
Base_Player_Controller :: struct #packed {
	// m_hPawn
	pawn_handle: u32 `0x06bc`,

	// m_iszPlayerName
	player_name: [128]u8 `0x06f4`,

	// m_SteamID
	steam_id: u64 `0x0780`,

	// m_bIsLocalPlayerController
	is_local_player: bool `0x0788`,
}

// C_BasePlayerWeapon {client}
// unused; fields merged into Weapon_State
Base_Player_Weapon :: struct #packed {
	// m_AttributeManager
	attribute_manager: Attribute_Container `0x11a8`,

	// m_iClip1
	remaining_ammo: i32 `0x1700`,
}

// C_CSWeaponBase {client}
// unused; fields merged into Weapon_State
Counter_Strike_Weapon_Base :: struct #packed {
	// m_bInReload
	is_reloading: bool `0x1814`,
}

// Base_Player_Weapon + Counter_Strike_Weapon_Base
Weapon_State :: struct #packed {
	// m_AttributeManager
	attribute_manager: Attribute_Container `0x11a8`,

	// m_iClip1
	remaining_ammo: i32 `0x1700`,

	// m_bInReload
	is_reloading: bool `0x1814`,
}
