package memowy

import "core:strings"
import "core:sys/windows"

find_process_id :: proc (process_name: string) -> (u32, Memowy_Error) {
    snapshot := windows.CreateToolhelp32Snapshot(windows.TH32CS_SNAPPROCESS, 0)
    defer windows.CloseHandle(snapshot)

    if snapshot == windows.INVALID_HANDLE_VALUE {
        return 0, Memowy_Error.SnapshotFail
    }

    entry: windows.PROCESSENTRY32W
    entry.dwSize = size_of(windows.PROCESSENTRY32W)

    if windows.Process32FirstW(snapshot, &entry) == windows.FALSE {
        return 0, Memowy_Error.ProcessNotFound
    }

    for {
        cur_process, err := windows.utf16_to_utf8(entry.szExeFile[:])
        if err == nil {
            if strings.equal_fold(cur_process, process_name) {
                delete(cur_process, context.temp_allocator)
                return entry.th32ProcessID, Memowy_Error.None
            }
            delete(cur_process, context.temp_allocator)
        }

        if windows.Process32NextW(snapshot, &entry) == windows.FALSE {
            break
        }
    }

    return 0, Memowy_Error.ProcessNotFound
}

open_process :: proc (pid: u32) -> (windows.HANDLE, Memowy_Error) {
    process := windows.OpenProcess(
        // windows.PROCESS_QUERY_INFORMATION |
        // windows.PROCESS_VM_OPERATION |
        windows.PROCESS_VM_READ,
        // windows.PROCESS_VM_WRITE,
        windows.FALSE,
        pid,
    )

    if process == nil {
        return nil, Memowy_Error.OpenProcessFail
    }

    return process, Memowy_Error.None
}

close_process :: proc (process: windows.HANDLE) -> bool {
    if process != nil && process != windows.INVALID_HANDLE_VALUE {
        windows.CloseHandle(process)
        return true
    }
    return false
}

Module_Info :: struct {
    base: uintptr,
    size: uint,
}

find_module :: proc (pid: u32, module_name: string) -> (Module_Info, Memowy_Error) {
    snapshot := windows.CreateToolhelp32Snapshot(
        windows.TH32CS_SNAPMODULE |
        windows.TH32CS_SNAPMODULE32,
        pid,
    )
    defer windows.CloseHandle(snapshot)

    if snapshot == windows.INVALID_HANDLE_VALUE {
        return {}, Memowy_Error.SnapshotFail
    }

    entry: windows.MODULEENTRY32W
    entry.dwSize = size_of(windows.MODULEENTRY32W)

    if windows.Module32FirstW(snapshot, &entry) == windows.FALSE {
        return {}, Memowy_Error.ModuleNotFound
    }

    for {
        cur_module, err := windows.utf16_to_utf8(entry.szModule[:])
        if err == nil {
            if strings.equal_fold(cur_module, module_name) {
                delete(cur_module, context.temp_allocator)

                return Module_Info {
                    base = uintptr(entry.modBaseAddr),
                    size = uint(entry.modBaseSize),
                }, Memowy_Error.None
            }

            delete(cur_module, context.temp_allocator)
        }

        if windows.Module32NextW(snapshot, &entry) == windows.FALSE {
            break
        }
    }

    return {}, Memowy_Error.ModuleNotFound
}

foreign import ntdll "system:ntdll.lib"

@(default_calling_convention="stdcall")
foreign ntdll {
    NtReadVirtualMemory :: proc (
        ProcessHandle: windows.HANDLE,
        BaseAddress: windows.PVOID,
        Buffer: windows.PVOID,
        NumberOfBytesToRead: windows.SIZE_T,
        NumberOfBytesRead: windows.PSIZE_T,
    ) -> windows.NTSTATUS ---

    NtWriteVirtualMemory :: proc (
        ProcessHandle: windows.HANDLE,
        BaseAddress: windows.PVOID,
        Buffer: windows.PVOID,
        NumberOfBytesToWrite: windows.SIZE_T,
        NumberOfBytesWritten: windows.PSIZE_T,
    ) -> windows.NTSTATUS ---
}

read_raw :: proc (
    process: windows.HANDLE,
    address: uintptr,
    buffer: rawptr,
    size: uint,
) -> Memowy_Error {
    bytes_read: uint

    status := NtReadVirtualMemory(
        process,
        rawptr(address),
        buffer,
        windows.SIZE_T(size),
        &bytes_read,
    )

    if status != 0 || bytes_read != size {
        return Memowy_Error.ReadError
    }

    return Memowy_Error.None
}

// write_raw :: proc (
//     process: windows.HANDLE,
//     address: uintptr,
//     buffer: rawptr,
//     size: uint,
// ) -> Memowy_Error {
//     bytes_written: uint
//
//     status := NtWriteVirtualMemory(
//         process,
//         rawptr(address),
//         buffer,
//         size,
//         &bytes_written,
//     )
//
//     if status != 0 || bytes_written != size {
//         return Memowy_Error.WriteError
//     }
//
//     return Memowy_Error.None
// }

read :: proc (
    process: windows.HANDLE,
    address: uintptr,
    out: ^$T,
) -> Memowy_Error {
    return read_raw(
        process,
        address,
        out,
        uint(size_of(T)),
    )
}

// write :: proc (
//     process: windows.HANDLE,
//     address: uintptr,
//     value: ^$T,
// ) -> Memowy_Error {
//     return write_raw(
//         process,
//         address,
//         value,
//         size_of(T),
//     )
// }

SIGNATURE_WILDCARD : u16 : 0xFFFF

// signature is actually []u8 but we use u16 so we can have a wildcard
find_signature_in_module :: proc (
    process: windows.HANDLE,
    module: Module_Info,
    signature: []u16,
) -> (uintptr, Memowy_Error) {
    sig_len := len(signature)

    if sig_len == 0 {
        return 0, Memowy_Error.SignatureNotFound
    }

    module_memory := make([]u8, module.size)
    defer delete(module_memory)

    rr_err := read_raw(process, module.base, raw_data(module_memory), module.size)
    if rr_err != Memowy_Error.None {
        return 0, rr_err
    }

    for i in 0..<(module.size - uint(sig_len) + 1) {
        matched := true

        for j in 0..<sig_len {
            b := signature[j]

            if
                b != SIGNATURE_WILDCARD &&
                module_memory[i + uint(j)] != u8(b)
            {
                matched = false
                break
            }
        }

        if matched {
            return module.base + uintptr(i), Memowy_Error.None
        }
    }

    return 0, Memowy_Error.SignatureNotFound
}
