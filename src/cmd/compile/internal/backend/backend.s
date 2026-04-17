package compile.internal.backend

use std.io.eprintln

// DEPRECATED: compile.internal.backend
// The old backend module delegated to an external native runner (s-native).
// This module is intentionally marked deprecated and now returns an error
// when invoked. Call sites should migrate away from this API and use the
// in-process hosted compiler or new self-hosted build path.

func Build(String path, String output) -> i32 {
    eprintln("error: compile.internal.backend.Build is deprecated;\n    please use the hosted compiler or the self-hosted build pipeline instead")
    1
}

func Run(String path) -> i32 {
    eprintln("error: compile.internal.backend.Run is deprecated;\n    please use the hosted compiler or run compiled artifacts directly")
    1
}

func BuildTrace(String path, String output) -> String {
    return "DEPRECATED: compile.internal.backend.BuildTrace"
}
