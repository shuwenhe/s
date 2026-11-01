package compile.internal.ir
func class_string_module_name() string {
    "ir/class_string.s"
}

func class_string_module_apply() int {
    0
}

// Storage class names, ported from ir/class_string.go (stringer for Class).
func class_string(int i) string {
    if i == 0 { return "Pxxx" }
    if i == 1 { return "PEXTERN" }
    if i == 2 { return "PAUTO" }
    if i == 3 { return "PAUTOHEAP" }
    if i == 4 { return "PPARAM" }
    if i == 5 { return "PPARAMOUT" }
    if i == 6 { return "PTYPEPARAM" }
    if i == 7 { return "PFUNC" }
    return "Class(?)"
}
