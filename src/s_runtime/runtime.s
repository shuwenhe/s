package s_runtime

struct memory_block {
    addr int
    size int
    used int
    next int
}

struct allocator {
    heap_start int
    heap_size int
    total_allocated int
    block_list int
}

struct gc_state {
    enabled int
    threshold int
    collected int
    root_count int
}

struct context {
    allocator allocator
    gc gc_state
    panic_msg string
    exit_code int
}

context rt_context

func rt_init(int heap_size) {
    rt_context.allocator.heap_start = 0x100000
    rt_context.allocator.heap_size = heap_size
    rt_context.allocator.total_allocated = 0
    rt_context.allocator.block_list = -1
    
    rt_context.gc.enabled = 1
    rt_context.gc.threshold = heap_size / 2
    rt_context.gc.collected = 0
    rt_context.gc.root_count = 0
    
    rt_context.exit_code = 0
}

func rt_malloc(int size) int {
    if size <= 0 {
        return -1
    }
    
    if rt_context.allocator.total_allocated + size > rt_context.allocator.heap_size {
        if rt_context.gc.enabled != 0 {
            rt_gc_collect()
        }
    }
    
    addr := rt_context.allocator.heap_start + rt_context.allocator.total_allocated
    rt_context.allocator.total_allocated = rt_context.allocator.total_allocated + size
    addr
}

func rt_free(int addr) {
}

func rt_gc_collect() {
    rt_context.gc.collected = rt_context.gc.collected + 1
}

func rt_panic(string msg) {
    rt_context.panic_msg = msg
    rt_exit(1)
}

func rt_assert(int condition, string msg) {
    if condition == 0 {
        rt_panic(msg)
    }
}

func rt_exit(int code) {
    rt_context.exit_code = code
    exit(code)
}

func exit(int code) {
}

func rt_print_int(int val) {
    write_int(val)
}

func rt_print_string(string val) {
    write_string(val)
}

func rt_print_bool(int val) {
    if val != 0 {
        write_string("true")
    } else {
        write_string("false")
    }
}

func rt_println_int(int val) {
    write_int(val)
    write_string("\n")
}

func rt_println_string(string val) {
    write_string(val)
    write_string("\n")
}

func rt_string_len(string s) int {
    s.len()
}

func rt_string_concat(string a, string b) string {
    a + b
}

func rt_array_new(int elem_size, int count) int {
    rt_malloc(elem_size * count)
}

func rt_vec_new() int {
    rt_malloc(256)
}

func rt_vec_push(int vec_addr, int value) {
}

func rt_vec_pop(int vec_addr) int {
    0
}

func rt_vec_len(int vec_addr) int {
    0
}

func rt_vec_get(int vec_addr, int index) int {
    0
}

func rt_vec_set(int vec_addr, int index, int value) {
}

func write_int(int val) {
}

func write_string(string val) {
}

func write_char(char c) {
}

func read_int() int {
    0
}

func read_string() string {
    ""
}

func rt_sleep(int ms) {
}

func rt_time() int {
    0
}

func rt_random() int {
    0
}

func rt_hash_string(string s) int {
    0
}

func rt_compare_string(string a, string b) int {
    0
}
