package remote

Error :: enum {
	None,
	Process_Not_Found,
	Module_Not_Found,
	Snapshot_Failed,
	Open_Process_Failed,
	Hijack_Failed,
	Signature_Not_Found,
	Read_Failed,
	Write_Failed,
	Span_Failed,
}
