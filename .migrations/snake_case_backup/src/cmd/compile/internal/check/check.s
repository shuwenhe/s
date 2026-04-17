package compile.internal.check

use compile.internal.semantic.CheckText
use std.fs.ReadToString

func LoadFrontend(string path) string {
    return ReadToString(path).unwrap()
}

func CheckFrontend(string frontend) int32 {
    return CheckText(frontend)
}
