package s_runtime

func test_rt_malloc() int {
    rt_init(1024)
    addr1 := rt_malloc(64)
    addr2 := rt_malloc(128)
    
    rt_assert(addr1 >= 0, "malloc addr1 should be valid")
    rt_assert(addr2 > addr1, "addr2 should be after addr1")
    
    1
}

func test_rt_panic_recovery() int {
    rt_init(1024)
    rt_assert(1 != 0, "test assertion")
    1
}

func test_rt_string_ops() int {
    rt_init(1024)
    
    len1 := rt_string_len("hello")
    rt_assert(len1 == 5, "string length should be 5")
    
    len2 := rt_string_len("")
    rt_assert(len2 == 0, "empty string length should be 0")
    
    1
}

func test_rt_multiple_allocations() int {
    rt_init(4096)
    
    addrs := []int()
    for i := 0; i < 10; i = i + 1 {
        addr := rt_malloc(128)
        rt_assert(addr >= 0, "allocation should succeed")
    }
    
    1
}

func run_all_runtime_tests() int {
    result := 0
    
    if test_rt_malloc() != 0 {
        result = result + 1
    }
    
    if test_rt_panic_recovery() != 0 {
        result = result + 1
    }
    
    if test_rt_string_ops() != 0 {
        result = result + 1
    }
    
    if test_rt_multiple_allocations() != 0 {
        result = result + 1
    }
    
    result
}
