package compile.internal.ssagen

func intrinsics_test_case_name() string {
    "ssagen/intrinsics_test.s"
}

func intrinsics_test_case_pass() int {
    if !has_intrinsic("runtime.memmove") {
        return 0
    }
    if intrinsic_op("runtime.memmove") != "MemMove" {
        return 0
    }
    if has_intrinsic("runtime.unknown") {
        return 0
    }
    1
}
