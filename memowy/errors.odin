package memowy

Memowy_Error :: enum {
    None,

    ProcessNotFound,
    ModuleNotFound,

    SnapshotFail,
    OpenProcessFail,

    InvalidHandle,
    InvalidOffset,

    SignatureNotFound,

    ReadError,
    WriteError,
}
