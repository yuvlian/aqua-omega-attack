package remote

import "core:strings"
import "core:sys/windows"

Process :: struct {
	pid:    u32,
	handle: windows.HANDLE,
}

Module_Info :: struct {
	base: uintptr,
	size: uint,
}

find_process :: proc (process_name: string) -> (u32, Error) {
	snapshot := windows.CreateToolhelp32Snapshot(windows.TH32CS_SNAPPROCESS, 0)
	if snapshot == windows.INVALID_HANDLE_VALUE {
		return 0, Error.Snapshot_Failed
	}
	defer windows.CloseHandle(snapshot)

	entry: windows.PROCESSENTRY32W
	entry.dwSize = size_of(windows.PROCESSENTRY32W)

	if windows.Process32FirstW(snapshot, &entry) == windows.FALSE {
		return 0, Error.Process_Not_Found
	}

	for {
		name, err := windows.utf16_to_utf8(entry.szExeFile[:])
		if err == nil {
			if strings.equal_fold(name, process_name) {
				delete(name, context.temp_allocator)
				return entry.th32ProcessID, Error.None
			}
			delete(name, context.temp_allocator)
		}

		if windows.Process32NextW(snapshot, &entry) == windows.FALSE {
			break
		}
	}

	return 0, Error.Process_Not_Found
}

// could prob make this and find_process reuse something
process_exists :: proc (pid: u32) -> bool {
	snapshot := windows.CreateToolhelp32Snapshot(windows.TH32CS_SNAPPROCESS, 0)
	if snapshot == windows.INVALID_HANDLE_VALUE {
		return false
	}
	defer windows.CloseHandle(snapshot)

	entry: windows.PROCESSENTRY32W
	entry.dwSize = size_of(windows.PROCESSENTRY32W)

	if windows.Process32FirstW(snapshot, &entry) == windows.FALSE {
		return false
	}

	for {
		if entry.th32ProcessID == pid {
			return true
		}
		if windows.Process32NextW(snapshot, &entry) == windows.FALSE {
			break
		}
	}

	return false
}

find_module :: proc (pid: u32, module_name: string) -> (Module_Info, Error) {
	snapshot := windows.CreateToolhelp32Snapshot(
		windows.TH32CS_SNAPMODULE | windows.TH32CS_SNAPMODULE32,
		pid,
	)
	if snapshot == windows.INVALID_HANDLE_VALUE {
		return {}, Error.Snapshot_Failed
	}
	defer windows.CloseHandle(snapshot)

	entry: windows.MODULEENTRY32W
	entry.dwSize = size_of(windows.MODULEENTRY32W)

	if windows.Module32FirstW(snapshot, &entry) == windows.FALSE {
		return {}, Error.Module_Not_Found
	}

	for {
		name, err := windows.utf16_to_utf8(entry.szModule[:])
		if err == nil {
			if strings.equal_fold(name, module_name) {
				delete(name, context.temp_allocator)
				return Module_Info {
					base = uintptr(entry.modBaseAddr),
					size = uint(entry.modBaseSize),
				}, Error.None
			}
			delete(name, context.temp_allocator)
		}

		if windows.Module32NextW(snapshot, &entry) == windows.FALSE {
			break
		}
	}

	return {}, Error.Module_Not_Found
}

read_typed :: proc (handle: windows.HANDLE, address: uintptr, out: ^$T) -> Error {
	return read_raw(handle, address, out, uint(size_of(T)))
}

read_raw :: proc (
	handle: windows.HANDLE,
	address: uintptr,
	buffer: rawptr,
	size: uint,
) -> Error {
	bytes_read: uint

	status := NtReadVirtualMemory(
		handle,
		rawptr(address),
		buffer,
		size,
		&bytes_read,
	)

	if status != 0 || bytes_read != size {
		return Error.Read_Failed
	}

	return Error.None
}

write_typed :: proc (handle: windows.HANDLE, address: uintptr, value: ^$T) -> Error {
	return write_raw(handle, address, value, uint(size_of(T)))
}

write_raw :: proc (
	handle: windows.HANDLE,
	address: uintptr,
	buffer: rawptr,
	size: uint,
) -> Error {
	bytes_written: uint

	status := NtWriteVirtualMemory(
		handle,
		rawptr(address),
		buffer,
		size,
		&bytes_written,
	)

	if status != 0 || bytes_written != size {
		return Error.Write_Failed
	}

	return Error.None
}

// write is currently unused
read  :: proc {read_typed, read_raw}
write :: proc {write_typed, write_raw}

SIGNATURE_WILDCARD :: max(u16)

find_signature_in_buffer :: proc (
	buffer: []u8,
	signature: []u16,
	base: uintptr,
) -> (uintptr, Error) {
	n := len(buffer)
	m := len(signature)

	if m == 0 || n < m {
		return 0, Error.Signature_Not_Found
	}

	last_concrete: [256]int
	for i in 0 ..< 256 {
		last_concrete[i] = -1
	}

	last_wildcard := -1
	for p in 0 ..< m - 1 {
		b := signature[p]
		if b == SIGNATURE_WILDCARD {
			last_wildcard = p
		} else {
			last_concrete[int(u8(b))] = p
		}
	}

	skip: [256]int
	for i in 0 ..< 256 {
		last := last_concrete[i]
		if last_wildcard > last {
			last = last_wildcard
		}

		shift := m - 1 - last
		if shift < 1 {
			shift = 1
		}

		skip[i] = shift
	}

	i := 0
	for i <= n - m {
		matched := true

		for j in 0 ..< m {
			b := signature[j]
			if b != SIGNATURE_WILDCARD && buffer[i + j] != u8(b) {
				matched = false
				break
			}
		}

		if matched {
			return base + uintptr(i), Error.None
		}

		i += skip[int(buffer[i + m - 1])]
	}

	return 0, Error.Signature_Not_Found
}

// unused but whatever
find_signature_in_module :: proc (
	handle: windows.HANDLE,
	module: Module_Info,
	signature: []u16,
	block: []u8,
) -> (uintptr, Error) {
	sig_len := len(signature)
	if sig_len == 0 {
		return 0, Error.Signature_Not_Found
	}

	block_size := uint(len(block))
	step := block_size - uint(sig_len - 1)

	off: uint = 0
	for off < module.size {
		size := min(module.size - off, block_size)

		err := read_raw(handle, module.base + uintptr(off), raw_data(block), size)
		if err != Error.None {
			off += step
			continue
		}

		if addr, scan_err := find_signature_in_buffer(
			block[:size],
			signature, 
			module.base + uintptr(off),
		); scan_err == Error.None {
			return addr, Error.None
		}

		off += step
	}

	return 0, Error.Signature_Not_Found
}
