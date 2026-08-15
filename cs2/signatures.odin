package cs2

import "core:fmt"
import "core:sys/windows"
import "../remote"

UNK :: remote.SIGNATURE_WILDCARD

RIP_DISP32_OFFSET   :: 3
RIP_INSTRUCTION_LEN :: 7

SCAN_BLOCK_SIZE :: 1 << 20

CSGO_INPUT_SIGNATURE :: []u16 {
	0x48, 0x89, 0x05,
	UNK, UNK, UNK, UNK,
	0x0F, 0x57, 0xC0,
	0x0F, 0x11, 0x05,
}

ENTITY_LIST_SIGNATURE :: []u16 {
	0x48, 0x89, 0x0D,
	UNK, UNK, UNK, UNK,
	0xE9,
	UNK, UNK, UNK, UNK,
	0xCC,
}

GAME_ENTITY_SYSTEM_SIGNATURE :: []u16 {
	0x48, 0x8B, 0x1D,
	UNK, UNK, UNK, UNK,
	0x48, 0x89, 0x1D,
	UNK, UNK, UNK, UNK,
	0x4C, 0x63, 0xB3,
}

GAME_RULES_SIGNATURE :: []u16 {
	0xF6, 0xC1, 0x01,
	0x0F, 0x85,
	UNK, UNK, UNK, UNK,
	0x4C, 0x8B, 0x05,
	UNK, UNK, UNK, UNK,
	0x4D, 0x85,
}

GLOBAL_VARS_SIGNATURE :: []u16 {
	0x48, 0x89, 0x15,
	UNK, UNK, UNK, UNK,
	0x48, 0x89, 0x42,
}

GLOW_MANAGER_SIGNATURE :: []u16 {
	0x48, 0x8B, 0x05,
	UNK, UNK, UNK, UNK,
	0xC3,
	0xCC, 0xCC, 0xCC, 0xCC,
	0xCC, 0xCC, 0xCC, 0xCC,
	0x8B, 0x41,
}

LOCAL_PLAYER_CONTROLLER_SIGNATURE :: []u16 {
	0x48, 0x8B, 0x05,
	UNK, UNK, UNK, UNK,
	0x41, 0x89, 0xBE,
}

PLANTED_C4_SIGNATURE :: []u16 {
	0x48, 0x8B, 0x1D,
	UNK, UNK, UNK, UNK,
	0x45, 0x32, 0xF6,
}

PREDICTION_SIGNATURE :: []u16 {
	0x48, 0x8D, 0x05,
	UNK, UNK, UNK, UNK,
	0xC3,
	0xCC, 0xCC, 0xCC, 0xCC,
	0xCC, 0xCC, 0xCC, 0xCC,
	0x40, 0x53, 0x56, 0x41, 0x54,
}

SENSITIVITY_SIGNATURE :: []u16 {
	0x48, 0x8D, 0x0D,
	UNK, UNK, UNK, UNK,
	UNK, UNK, UNK, UNK,
	0x66, 0x0F, 0x6E, 0xCD,
}

VIEW_MATRIX_SIGNATURE :: []u16 {
	0x48, 0x8D, 0x0D,
	UNK, UNK, UNK, UNK,
	0x48, 0xC1, 0xE0, 0x06,
}

VIEW_RENDER_SIGNATURE :: []u16 {
	0x48, 0x89, 0x05,
	UNK, UNK, UNK, UNK,
	0x48, 0x8B, 0xC8,
	0x48, 0x85, 0xC0,
}

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
}

find_offsets :: proc (
	handle: windows.HANDLE,
	client: remote.Module_Info,
) -> (Offsets, remote.Error) {
	offsets: Offsets

	block := make([]u8, SCAN_BLOCK_SIZE)
	defer delete(block)

	patches := []struct {
		name:   string,
		sig:    []u16,
		found:  bool,
		target: ^uintptr,
	} {
		{name = "view_matrix", sig = VIEW_MATRIX_SIGNATURE, target = &offsets.view_matrix},
		{name = "entity_list", sig = ENTITY_LIST_SIGNATURE, target = &offsets.entity_list},
		{name = "global_vars", sig = GLOBAL_VARS_SIGNATURE, target = &offsets.global_vars},
		{name = "planted_c4",  sig = PLANTED_C4_SIGNATURE,  target = &offsets.planted_c4},
		{name = "weapon_c4",   sig = WEAPON_C4_SIGNATURE,   target = &offsets.weapon_c4},
	}

	max_sig := 0
	for p in patches {
		max_sig = max(max_sig, len(p.sig))
	}
	if max_sig == 0 {
		return {}, remote.Error.Signature_Not_Found
	}

	step := uint(SCAN_BLOCK_SIZE) - uint(max_sig - 1)

	off: uint = 0
	for off < client.size {
		size := min(client.size - off, uint(SCAN_BLOCK_SIZE))

		if remote.read_raw(
			handle,
			client.base + uintptr(off),
			raw_data(block),
			size,
		) == remote.Error.None {
			base := client.base + uintptr(off)
			for &p in patches {
				if p.found {
					continue
				}

				if match, scan_err := remote.find_signature_in_buffer(
					block[:size], p.sig, base,
				); scan_err == remote.Error.None {
					disp32: i32
					if read_err := remote.read(
						handle,
						match + RIP_DISP32_OFFSET,
						&disp32,
					); read_err == remote.Error.None {
						p.target^ = match + 
							RIP_INSTRUCTION_LEN + uintptr(disp32) - client.base
						p.found = true
						fmt.printf("found %s offset at 0x%x\n", p.name, p.target^)
					}
				}
			}
		}

		off += step
	}

	for p in patches {
		if !p.found {
			return {}, remote.Error.Signature_Not_Found
		}
	}

	return offsets, remote.Error.None
}
