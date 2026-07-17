package cs2

import m "../memowy"

// CPlayer_ObserverServices {client}
Player_Observer_Services :: struct #packed {
    // m_hObserverTarget
    observer_target: uintptr `0x4c`,
}

// C_AtributeContainer {client}
Attribute_Container :: struct #packed {
    // m_Item
    item: Econ_Item_View `0x50`,
}

// CPlayer_WeaponServices {client}
Player_Weapon_Services :: struct #packed {
    // m_hActiveWeapon
    active_weapon_handle: uintptr `0x60`,
}

// CGameSceneNode {client}
Game_Scene_Node :: struct #packed {
    // m_vecAbsOrigin
    absolute_origin: [3]f32 `0xc8`,

    // undocumented? m_modelState (0x0140) + 0x80
    bone_array_ptr: uintptr `0x01C0`,
}

// Undocumented
Global_Vars :: struct #packed {
    map_name: [32]u8 `0x180`,
}

// C_EconItemView {client}
Econ_Item_View :: struct #packed {
    // m_iItemDefinitionIndex
    definition_index: u16 `0x1BA`,
}

// C_PlantedC4 {client}
Planted_C4 :: struct #packed {
    // m_nBombSite
    bomb_site: i32 `0x11A4`,

    // m_pGameSceneNode
    game_scene_node_ptr: uintptr `0x0330`,
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

    // m_vOldOrigin
    old_origin: [3]f32 `0x13b8`,

    // m_flFlashOverlayAlpha
    flash_alpha: f32 `0x141c`,

    // m_bIsScoped
    is_scoping: bool `0x1c70`,

    // m_bIsDefusing
    is_defusing: bool `0x1c72`,

    // m_entitySpottedState->m_bSpottedByMask
    // 0x1c58 + 0x0c
    spotted_mask: [2]u32 `0x1C64`,

    // m_pWeaponServices
    weapon_services_ptr: uintptr `0x1208`,

    // m_pObserverServices
    observer_services_ptr: uintptr `0x1220`,
}

// CBasePlayerController {client}
Base_Player_Controller :: struct #packed {
    // m_hPawn
    pawn_handle: uintptr `0x06bc`,

    // m_iszPlayerName
    player_name: [128]u8 `0x06f4`,

    // m_SteamID
    steam_id: u64 `0x0780`,

    // m_bIsLocalPlayerController
    is_local_player: bool `0x0788`,
}

// C_BasePlayerWeapon {client}
Base_Player_Weapon :: struct #packed {
    // m_AttributeManager
    attribute_manager: Attribute_Container `0x11a8`,

    // m_iClip1
    remaining_ammo: i32 `0x1700`,
}

// C_CSWeaponBase {client}
Counter_Strike_Weapon_Base :: struct #packed {
    // m_bInReload
    is_reloading: bool `0x1814`,
}

UNK :: m.SIGNATURE_WILDCARD

CSGO_INPUT_SIGNATURE :: []u16 {
    0x48, 0x89, 0x05,
    UNK, UNK, UNK, UNK,
    0x0F, 0x57, 0xC0,
    0x0F, 0x11, 0x05,
};

ENTITY_LIST_SIGNATURE :: []u16 {
    0x48, 0x89, 0x0D,
    UNK, UNK, UNK, UNK,
    0xE9,
    UNK, UNK, UNK, UNK,
    0xCC,
};

GAME_ENTITY_SYSTEM_SIGNATURE :: []u16 {
    0x48, 0x8B, 0x1D,
    UNK, UNK, UNK, UNK,
    0x48, 0x89, 0x1D,
    UNK, UNK, UNK, UNK,
    0x4C, 0x63, 0xB3,
};

GAME_RULES_SIGNATURE :: []u16 {
    0xF6, 0xC1, 0x01,
    0x0F, 0x85,
    UNK, UNK, UNK, UNK,
    0x4C, 0x8B, 0x05,
    UNK, UNK, UNK, UNK,
    0x4D, 0x85,
};

GLOBAL_VARS_SIGNATURE :: []u16 {
    0x48, 0x89, 0x15,
    UNK, UNK, UNK, UNK,
    0x48, 0x89, 0x42,
};

GLOW_MANAGER_SIGNATURE :: []u16 {
    0x48, 0x8B, 0x05,
    UNK, UNK, UNK, UNK,
    0xC3,
    0xCC, 0xCC, 0xCC, 0xCC,
    0xCC, 0xCC, 0xCC, 0xCC,
    0x8B, 0x41,
};

LOCAL_PLAYER_CONTROLLER_SIGNATURE :: []u16 {
    0x48, 0x8B, 0x05,
    UNK, UNK, UNK, UNK,
    0x41, 0x89, 0xBE,
};

PLANTED_C4_SIGNATURE :: []u16 {
    0x48, 0x8B, 0x1D,
    UNK, UNK, UNK, UNK,
    0x45, 0x32, 0xF6,
};

PREDICTION_SIGNATURE :: []u16 {
    0x48, 0x8D, 0x05,
    UNK, UNK, UNK, UNK,
    0xC3,
    0xCC, 0xCC, 0xCC, 0xCC,
    0xCC, 0xCC, 0xCC, 0xCC,
    0x40, 0x53, 0x56, 0x41, 0x54,
};

SENSITIVITY_SIGNATURE :: []u16 {
    0x48, 0x8D, 0x0D,
    UNK, UNK, UNK, UNK,
    UNK, UNK, UNK, UNK,
    0x66, 0x0F, 0x6E, 0xCD,
};

VIEW_MATRIX_SIGNATURE :: []u16 {
    0x48, 0x8D, 0x0D,
    UNK, UNK, UNK, UNK,
    0x48, 0xC1, 0xE0, 0x06,
};

VIEW_RENDER_SIGNATURE :: []u16 {
    0x48, 0x89, 0x05,
    UNK, UNK, UNK, UNK,
    0x48, 0x8B, 0xC8,
    0x48, 0x85, 0xC0,
};

WEAPON_C4_SIGNATURE :: []u16 {
    0x48, 0x8B, 0x15,
    UNK, UNK, UNK, UNK,
    0x48, 0x8B, 0x5C, 0x24,
    UNK,
    0xFF, 0xC0,
    0x89, 0x05,
    UNK, UNK, UNK, UNK,
    0x48, 0x8B, 0xC6,
    0x48, 0x89, 0x34, 0xEA,
    0x80, 0xBE,
};
