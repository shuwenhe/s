package compile.internal.arch

func Init(String arch) -> String {
    if arch == "amd64" {
        return ""
    } else if arch == "arm64" {
        return ""
    } else if arch == "riscv64" {
        return ""
    } else if arch == "amd64p32" {
        return ""
    } else if arch == "s390x" {
        return ""
    } else if arch == "wasm" {
        return ""
    } else {
        "unknown architecture \"" + arch + "\""
    }
}
