package main

import "core:fmt"
import "./memowy"

main :: proc () {
    pid, err := memowy.find_process_id("notepad.exe")
    if err != memowy.Memowy_Error.None {
        fmt.printf("find_process_id failed: %v\n", err)
        return
    }

    module, err1 := memowy.find_module(pid, "ntdll.dll")
    if err1 != memowy.Memowy_Error.None {
        fmt.printf("find_module failed: %v\n", err)
        return
    }

    process, err2 := memowy.open_process(pid)
    if err2 != memowy.Memowy_Error.None {
        fmt.printf("open_process failed: %v\n", err)
        return
    }
    defer memowy.close_process(process)

    dos_header: [64]u8

    err = memowy.read(
        process,
        module.base,
        &dos_header,
    )

    if err != memowy.Memowy_Error.None {
        fmt.printf("read failed: %v\n", err)
        return
    }

    fmt.printf("magic (should be MZ): %c%c\n", dos_header[0], dos_header[1])
}
