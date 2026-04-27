package src.runtime.secret

func alloc_test_unit_name() string {
    "src/runtime/secret/alloc_test"
}

func alloc_test_unit_ready() int {
    1
}

func main() int {
    if alloc_test_unit_ready() == 1 {
        return 0
    }
    return 1
}
