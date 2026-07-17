package cs2

import "core:sys/windows"
import m "../memowy"

CS2_PROCESS_NAME :: "cs2.exe"

CS2_Process :: struct {
    pid: u32,
    handle: windows.HANDLE
}

open_cs2 :: proc () -> (CS2_Process, m.Memowy_Error) {
    pid, find_pid_err := m.find_process_id(CS2_PROCESS_NAME)
    if find_pid_err != m.Memowy_Error.None {
        return {}, find_pid_err
    }

    handle, open_process_err := m.open_process(pid)
    if open_process_err != m.Memowy_Error.None {
        return {}, open_process_err
    }

    return CS2_Process {
        pid = pid,
        handle = handle,
    }, .None
}

close_cs2 :: proc (cs2: ^CS2_Process) {
    cs2.pid = 0
    if m.close_process(cs2.handle) {
        cs2.handle = nil
    }
}

