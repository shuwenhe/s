package compile.internal.check

use compile.internal.semantic.CheckText
use std.fs.ReadToString

func LoadFrontend(String path) -> String {
    return ReadToString(path).unwrap()
}

func CheckFrontend(String frontend) -> i32 {
    return CheckText(frontend)
}
