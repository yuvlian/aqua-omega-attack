package remote

import "core:sys/windows"

foreign import ntdll "system:ntdll.lib"

@(default_calling_convention = "stdcall")
foreign ntdll {
	NtReadVirtualMemory :: proc (
		ProcessHandle:       windows.HANDLE,
		BaseAddress:         windows.PVOID,
		Buffer:              windows.PVOID,
		NumberOfBytesToRead: windows.SIZE_T,
		NumberOfBytesRead:   windows.PSIZE_T,
	) -> windows.NTSTATUS ---

	NtWriteVirtualMemory :: proc (
		ProcessHandle:         windows.HANDLE,
		BaseAddress:           windows.PVOID,
		Buffer:                windows.PVOID,
		NumberOfBytesToWrite:  windows.SIZE_T,
		NumberOfBytesWritten:  windows.PSIZE_T,
	) -> windows.NTSTATUS ---

	NtQuerySystemInformation :: proc (
		SystemInformationClass:  u32, // SYSTEM_INFORMATION_CLASS (no core binding)
		SystemInformation:       windows.PVOID,
		SystemInformationLength: windows.ULONG,
		ReturnLength:            ^windows.ULONG,
	) -> windows.NTSTATUS ---

	NtDuplicateObject :: proc (
		SourceProcessHandle: windows.HANDLE,
		SourceHandle:        windows.HANDLE,
		TargetProcessHandle: windows.HANDLE,
		TargetHandle:        ^windows.HANDLE,
		DesiredAccess:       windows.ACCESS_MASK,
		HandleAttributes:    windows.ULONG,
		Options:             windows.ULONG,
	) -> windows.NTSTATUS ---
}

SYSTEM_EXTENDED_HANDLE_INFORMATION :: 64
STATUS_INFO_LENGTH_MISMATCH :: windows.NTSTATUS(-1073741820) // 0xC0000004
STATUS_ACCESS_DENIED        :: windows.NTSTATUS(-1073741790) // 0xC0000022

System_Handle_Entry :: struct #packed {
	object:                   windows.PVOID,     // offset 0
	unique_process_id:        windows.ULONG_PTR, // offset 8
	handle_value:             windows.ULONG_PTR, // offset 16
	granted_access:           windows.ULONG,     // offset 24
	creator_back_trace_index: windows.USHORT,    // offset 28
	object_type_index:        windows.USHORT,    // offset 30
	handle_attributes:        windows.ULONG,     // offset 32
	reserved:                 windows.ULONG,     // offset 36
}
