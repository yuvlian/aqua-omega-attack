package main

import "core:fmt"
import "core:mem"
import "./cs2"
import m "./memowy"

write_field :: proc (buffer: []u8, span_base: int, tag_offset: int, value: $T) {
    value := value
    off := tag_offset - span_base
    dst := buffer[off:off + size_of(T)]
    src := mem.byte_slice(&value, size_of(T))
    copy(dst, src)
}

test_span :: proc() {
    fmt.println("span test")
    fmt.println("=========")

    plan := m.build_copy_plan(cs2.Counter_Strike_Player_Pawn)
    fmt.printf("%#v\n\n", plan)

    buffer := make([]u8, plan.span.total_bytes)
    defer delete(buffer)

    write_field(buffer, plan.span.base_offset, 0x0330, uintptr(0xDEAD_BEEF))
    write_field(buffer, plan.span.base_offset, 0x034c, i32(100))
    write_field(buffer, plan.span.base_offset, 0x03e7, u8(2))
    write_field(buffer, plan.span.base_offset, 0x03f8, [3]f32{1, 2, 3})
    write_field(buffer, plan.span.base_offset, 0x1208, uintptr(0xCAFE_BABE))
    write_field(buffer, plan.span.base_offset, 0x1220, uintptr(0xFEED_FACE))
    write_field(buffer, plan.span.base_offset, 0x13b8, [3]f32{4, 5, 6})
    write_field(buffer, plan.span.base_offset, 0x141c, f32(0.75))
    write_field(buffer, plan.span.base_offset, 0x1c64, [2]u32{0xAAAA, 0xBBBB})
    write_field(buffer, plan.span.base_offset, 0x1c70, true)
    write_field(buffer, plan.span.base_offset, 0x1c72, false)

    result := m.apply_copy_plan(buffer, plan, cs2.Counter_Strike_Player_Pawn)

    fmt.printf("%#v\n", result)

    assert(result.game_scene_node_ptr == uintptr(0xDEAD_BEEF))
    assert(result.health == 100)
    assert(result.team_num == u8(2))
    assert(result.velocity == [3]f32{1, 2, 3})
    assert(result.weapon_services_ptr == uintptr(0xCAFE_BABE))
    assert(result.observer_services_ptr == uintptr(0xFEED_FACE))
    assert(result.old_origin == [3]f32{4, 5, 6})
    assert(result.flash_alpha == f32(0.75))
    assert(result.spotted_mask == [2]u32{0xAAAA, 0xBBBB})
    assert(result.is_scoping == true)
    assert(result.is_defusing == false)

    fmt.println("\nall assertions passed")
}

test_read :: proc() {
    fmt.println("memory read test")
    fmt.println("================")

    pid, err := m.find_process_id("notepad.exe")
    if err != m.Memowy_Error.None {
        fmt.printf("find_process_id failed: %v\n", err)
        return
    }

    module, err1 := m.find_module(pid, "ntdll.dll")
    if err1 != m.Memowy_Error.None {
        fmt.printf("find_module failed: %v\n", err1)
        return
    }

    process, err2 := m.open_process(pid)
    if err2 != m.Memowy_Error.None {
        fmt.printf("open_process failed: %v\n", err2)
        return
    }
    defer m.close_process(process)

    dos_header: [64]u8
    err3 := m.read(process, module.base, &dos_header)
    if err3 != m.Memowy_Error.None {
        fmt.printf("read failed: %v\n", err3)
        return
    }

    fmt.printf("notepad.exe pid: %v\n", pid)
    fmt.printf("ntdll base: 0x%x\n", module.base)
    fmt.printf("wildcard as (u16, char): (%v, %c)\n\n", m.SIGNATURE_WILDCARD, m.SIGNATURE_WILDCARD)

    fmt.println("read 64 bytes")
    fmt.printf("first two: %c\n\n", dos_header[0:2])

    signatures := []struct {
        name: string,
        sig: []u16,
    }{
        {
            "MZ",
            {'M','Z'},
        },
        {
            "M?",
            {'M',m.SIGNATURE_WILDCARD},
        },
        {
            "This program",
            {'T','h','i','s',' ','p','r','o','g','r','a','m'},
        },
        {
            "This??rogram",
            {'T','h','i','s',m.SIGNATURE_WILDCARD,m.SIGNATURE_WILDCARD,'r','o','g','r','a','m'},
        },
    }

    for s in signatures {
        fmt.printf("finding %v\n", s.name)

        addr, err := m.find_signature_in_module(process, module, s.sig)
        if err != m.Memowy_Error.None {
            fmt.printf("find_signature_in_module failed: %v\n", err)
            return
        }

        fmt.printf("%c found at: 0x%x\n\n", s.sig, addr)
    }
}

main :: proc() {
    test_read()
    fmt.println()
    test_span()
}
