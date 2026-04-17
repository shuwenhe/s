package compile.internal.build.backend

use std.io.eprintln

// DEPRECATED: compile.internal.build.backend
// This module previously delegated to the `s-native` runner. It's deprecated
// to reduce external-runner reliance. Call sites should migrate to the
// hosted compiler or self-hosted build pipeline.

func Build(String path, String output) -> i32 {
    eprintln("error: compile.internal.build.backend.Build is deprecated; use hosted compiler or self-hosted build instead")
    1
}

func Run(String path) -> i32 {
    eprintln("error: compile.internal.build.backend.Run is deprecated; use hosted compiler or run artifacts directly")
    1
}
