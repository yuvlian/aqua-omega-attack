package remote

import "core:fmt"
import "core:sys/windows"

Handle_Owner :: struct {
	pid:            u32,
	handle_value:   uint,
	granted_access: u32,
}

open_process :: proc (pid: u32, access: windows.DWORD) -> (windows.HANDLE, Error) {
	handle := windows.OpenProcess(access, windows.FALSE, pid)
	if handle == nil {
		return nil, Error.Open_Process_Failed
	}
	return handle, Error.None
}

close_process :: proc (handle: windows.HANDLE) {
	if handle != nil && handle != windows.INVALID_HANDLE_VALUE {
		windows.CloseHandle(handle)
	}
}

enumerate_handle_owners :: proc (
	target_pid: u32,
	allocator := context.allocator
) -> []Handle_Owner {
	self_pid := windows.GetCurrentProcessId()

	self_handle := windows.OpenProcess(
		windows.PROCESS_QUERY_INFORMATION, windows.FALSE, self_pid)
	if self_handle == nil {
		return nil
	}
	defer windows.CloseHandle(self_handle)

	owners := make([dynamic]Handle_Owner, allocator)

	buffer_len: windows.ULONG = 64 * 1024
	for {
		buffer := make([]u8, int(buffer_len), context.allocator)
		defer delete(buffer)

		return_len: windows.ULONG
		status := NtQuerySystemInformation(
			SYSTEM_EXTENDED_HANDLE_INFORMATION,
			rawptr(raw_data(buffer)),
			buffer_len,
			&return_len,
		)

		if status == STATUS_INFO_LENGTH_MISMATCH {
			buffer_len *= 2
			continue
		}

		if status != 0 {
			return owners[:]
		}

		count := (^uint)(raw_data(buffer))^
		entries := cast([^]System_Handle_Entry)raw_data(buffer[16:])

		process_type_index: u16 = 0
		for i in 0 ..< int(count) {
			e := entries[i]
			if u32(e.unique_process_id) == self_pid &&
				e.handle_value == transmute(uint)self_handle {
				process_type_index = e.object_type_index
				break
			}
		}

		for i in 0 ..< int(count) {
			e := entries[i]
			if e.object_type_index != process_type_index {
				continue
			}

			src := windows.OpenProcess(
				windows.PROCESS_DUP_HANDLE, windows.FALSE, u32(e.unique_process_id))
			if src == nil {
				continue
			}

			probe: windows.HANDLE
			dup_status := NtDuplicateObject(
				src,
				transmute(windows.HANDLE)e.handle_value,
				windows.GetCurrentProcess(),
				&probe,
				windows.PROCESS_QUERY_LIMITED_INFORMATION,
				0,
				0,
			)

			if dup_status == 0 && windows.GetProcessId(probe) == target_pid {
				append(&owners, Handle_Owner {
					pid            = u32(e.unique_process_id),
					handle_value   = e.handle_value,
					granted_access = u32(e.granted_access),
				})
			}

			if probe != nil {
				windows.CloseHandle(probe)
			}
			windows.CloseHandle(src)
		}

		return owners[:]
	}
}

PROCESS_DESIRED_READ :: windows.PROCESS_VM_READ |
	windows.PROCESS_QUERY_INFORMATION

// we currently not write at all
PROCESS_DESIRED_WRITE :: PROCESS_DESIRED_READ |
	windows.PROCESS_VM_WRITE |
	windows.PROCESS_VM_OPERATION

hijack_handle :: proc (target_pid: u32) -> (windows.HANDLE, Error) {
	owners := enumerate_handle_owners(target_pid)
	defer delete(owners)

	self_pid := windows.GetCurrentProcessId()

	for owner in owners {
		if owner.pid == 0 ||
			owner.pid == 4 ||
			owner.pid == self_pid ||
			owner.pid == target_pid ||
			owner.granted_access & windows.PROCESS_VM_READ == 0 {
			continue
		}

		src := windows.OpenProcess(windows.PROCESS_DUP_HANDLE, windows.FALSE, owner.pid)
		if src == nil {
			continue
		}

		result: windows.HANDLE
		status := NtDuplicateObject(
			src,
			transmute(windows.HANDLE)owner.handle_value,
			windows.GetCurrentProcess(),
			&result,
			PROCESS_DESIRED_READ,
			0,
			0,
		)

		if status == 0 {
			windows.CloseHandle(src)

			confirmed := windows.GetProcessId(result) == target_pid
			if !confirmed {
				windows.CloseHandle(result)
				continue
			} else {
				fmt.printf(
					"hijacked cs2 handle: source_pid=%d, handle=0x%x\n",
					owner.pid,
					owner.handle_value,
				)
			}

			return result, Error.None
		}

		windows.CloseHandle(src)
	}

	fmt.println("failed to hijack handle")
	fmt.println("you can try waiting for the game to load properly and run this as admin")
	fmt.println("will fall back to direct OpenProcess this time")
	return open_process(target_pid, PROCESS_DESIRED_READ)
}
