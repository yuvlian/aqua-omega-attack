package main

import "core:fmt"
import m "./memowy"

main :: proc () {
    pid, err0 := m.find_process_id("notepad.exe")
    if err0 != m.Memowy_Error.None {
        fmt.printf("find_process_id failed: %v\n", err0)
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
    err3 := m.read(
        process,
        module.base,
        &dos_header,
    )
    if err3 != m.Memowy_Error.None {
        fmt.printf("read failed: %v\n", err3)
        return
    }

    fmt.printf("notepad.exe pid: %v\n", pid)
    fmt.printf("ntdll base: 0x%x\n", module.base)
    fmt.printf("wildcard as (u16, char): (%v, %c)\n\n", m.SIGNATURE_WILDCARD, m.SIGNATURE_WILDCARD)

    fmt.println("read 64 bytes")
    fmt.printf("first two: %c\n\n", dos_header[0:2])

    mz_sig := []u16{'M','Z'}
    mz_sig_addr, err4 := m.find_signature_in_module(process, module, mz_sig)

    fmt.printf("finding %c\n", mz_sig)
    if err4 != m.Memowy_Error.None {
        fmt.printf("find_signature_in_module failed: %v\n", err4)
        return
    }
    fmt.printf("%c found at: 0x%x\n\n", mz_sig, mz_sig_addr)

    mz_sig_wild := []u16{'M', m.SIGNATURE_WILDCARD}
    mz_sig_wild_addr, err5 := m.find_signature_in_module(process, module, mz_sig_wild)

    fmt.printf("finding %c\n", mz_sig_wild)
    if err5 != m.Memowy_Error.None {
        fmt.printf("find_signature_in_module failed: %v\n", err5)
        return
    }
    fmt.printf("%c found at: 0x%x\n\n", mz_sig_wild, mz_sig_wild_addr)

    this_program_sig := []u16{'T','h','i','s',' ','p','r','o','g','r','a','m'}
    this_program_sig_addr, err6 := m.find_signature_in_module(process, module, this_program_sig)

    fmt.printf("finding %c\n", this_program_sig)
    if err6 != m.Memowy_Error.None {
        fmt.printf("find_signature_in_module failed: %v\n", err6)
        return
    }
    fmt.printf("%c found at: 0x%x\n\n", this_program_sig, this_program_sig_addr)

    this_program_sig_wild := []u16{'T','h','i','s',m.SIGNATURE_WILDCARD,m.SIGNATURE_WILDCARD,'r','o','g','r','a','m'}
    this_program_sig_wild_addr, err7 := m.find_signature_in_module(process, module, this_program_sig_wild)

    fmt.printf("finding %c\n", this_program_sig_wild)
    if err7 != m.Memowy_Error.None {
        fmt.printf("find_signature_in_module failed: %v\n", err7)
        return
    }
    fmt.printf("%c found at: 0x%x\n", this_program_sig_wild, this_program_sig_wild_addr)
}
