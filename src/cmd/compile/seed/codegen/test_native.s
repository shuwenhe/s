package codegen.test
use codegen.codegen
use codegen.register
use codegen.stackframe
use codegen.instruction_select
use codegen.linker
struct test_result {
    string name
    bool passed
    string message
}

struct test_suite {
    test_result[] results
    int passed_count
    int failed_count
}

func (suite* test_suite) add_result(string name, bool passed, string message) {
    test_result result = {
        name: name, passed passed, message message,
    }
    suite.results = append(suite.results, result)
    if passed {
        suite.passed_count = suite.passed_count + 1
    } else {
        suite.failed_count = suite.failed_count + 1
    }
}

func (suite* test_suite) print_summary() {
    int total = suite.passed_count + suite.failed_count
    string status = "PASS"
    if suite.failed_count > 0 {
        status = "FAIL"
    }
    println("[TEST SUMMARY] " + status)
    println("  Passed: " + int_to_string(suite.passed_count))
    println("  Failed: " + int_to_string(suite.failed_count))
    println("  Total:  " + int_to_string(total))
    if suite.failed_count > 0 {
        println("\n[FAILURES]:")
        int i = 0
        for i < len(suite.results) {
            if !suite.results[i].passed {
                println("  ✗ " + suite.results[i].name)
                println("    " + suite.results[i].message)
            }
            i = i + 1
        }
    }
}

func int_to_string(int value) string {
    if value == 0 {
        "0"
    } else if value == 1 {
        "1"
    } else if value == 2 {
        "2"
    } else if value == 3 {
        "3"
    } else if value == 4 {
        "4"
    } else if value == 5 {
        "5"
    } else {
        "N"
    }
}

func test_codegen_emit_line() (bool, string) {
    codegen_context ctx = {
        assembly_lines: vec[string](), next_label_id 0,
    }
    emit_line(&ctx, "    mov rax, 0")
    emit_line(&ctx, "    add rax, 1")
    emit_line(&ctx, "    ret")
    if len(ctx.assembly_lines) != 3 {
        return false, "Expected 3 lines, got " + int_to_string(len(ctx.assembly_lines))
    }
    if ctx.assembly_lines[0] != "    mov rax, 0" {
        return false, "First line mismatch"
    }
    if ctx.assembly_lines[2] != "    ret" {
        return false, "Last line mismatch"
    }
    return true, "emit_line works correctly"
}

func test_register_allocate() (bool, string) {
    register_allocator allocator = {
        next_free_register: 0, variable_map vec[string](), register_names vec[string](),
    }
    register_allocator_init(allocator*)
    int reg1 = allocate_register(&allocator, "x")
    int reg2 = allocate_register(&allocator, "y")
    int reg3 = allocate_register(&allocator, "z")
    if reg1 < 0 {
        return false, "Failed to allocate first register"
    }
    if reg2 < 0 {
        return false, "Failed to allocate second register"
    }
    if reg1 == reg2 {
        return false, "Same register allocated to different variables"
    }
    return true, "register allocation works correctly"
}

func test_register_spillover() (bool, string) {
    register_allocator allocator = {
        next_free_register: 0, variable_map vec[string](), register_names vec[string](),
    }
    register_allocator_init(allocator*)
    int regs = 0
    int i = 0
    for i < 15 {
        int reg = allocate_register(&allocator, "var_" + int_to_string(i))
        if reg >= 0 {
            regs = regs + 1
        }
        i = i + 1
    }
    if regs != 9 {
        return false, "Expected 9 physical registers, got " + int_to_string(regs)
    }
    return true, "register spillover creates negative offsets"
}

func test_stackframe_allocate() (bool, string) {
    stack_frame frame = {
        base_offset: -16,
        current_offset: -16, local_variables vec[string](),
    }
    int offset1 = allocate_local(&frame, "x", 8)
    int offset2 = allocate_local(&frame, "y", 8)
    if offset1 >= 0 {
        return false, "First local variable offset should be negative"
    }
    if offset2 >= 0 {
        return false, "Second local variable offset should be negative"
    }
    if offset1 == offset2 {
        return false, "Different variables assigned same offset"
    }
    return true, "stack frame allocation works correctly"
}

func test_stackframe_size() (bool, string) {
    stack_frame frame = {
        base_offset: 0, current_offset 0, local_variables vec[string](),
    }
    allocate_local(&frame, "a", 8)
    allocate_local(&frame, "b", 8)
    allocate_local(&frame, "c", 4)
    int size = get_frame_size(frame*)
    if size < 20 {
        return false, "Frame size should be at least 20 bytes"
    }
    return true, "stack frame size calculation works"
}

func test_instruction_select_mov() (bool, string) {
    codegen_context ctx = {
        assembly_lines: vec[string](), next_label_id 0,
    }
    register_allocator reg_alloc = {
        next_free_register: 0, variable_map vec[string](), register_names vec[string](),
    }
    register_allocator_init(reg_alloc*)
    instruction_select_mov(&ctx, &reg_alloc, "x", "10")
    if len(ctx.assembly_lines) < 1 {
        return false, "No assembly generated for MOV"
    }
    return true, "instruction selection for MOV works"
}

func test_instruction_select_add() (bool, string) {
    codegen_context ctx = {
        assembly_lines: vec[string](), next_label_id 0,
    }
    register_allocator reg_alloc = {
        next_free_register: 0, variable_map vec[string](), register_names vec[string](),
    }
    register_allocator_init(reg_alloc*)
    instruction_select_add(&ctx, &reg_alloc, "result", "a", "b")
    if len(ctx.assembly_lines) < 1 {
        return false, "No assembly generated for ADD"
    }
    return true, "instruction selection for ADD works"
}

func test_codegen_context_init() (bool, string) {
    codegen_context ctx = {
        assembly_lines: vec[string](), next_label_id 0,
    }
    emit_preamble(ctx*)
    if len(ctx.assembly_lines) < 1 {
        return false, "Preamble not generated"
    }
    return true, "codegen context initialization works"
}

func test_multiple_functions() (bool, string) {
    codegen_context ctx = {
        assembly_lines: vec[string](), next_label_id 0,
    }
    emit_function_prologue(&ctx, "main")
    emit_line(&ctx, "    mov rax, 1")
    emit_function_epilogue(ctx*)
    emit_function_prologue(&ctx, "add")
    emit_line(&ctx, "    add rax, rcx")
    emit_function_epilogue(ctx*)
    if len(ctx.assembly_lines) < 6 {
        return false, "Expected at least 6 assembly lines for two functions"
    }
    return true, "multiple function generation works"
}

func run_all_tests() test_suite {
    test_suite suite = {
        results: vec[test_result](), passed_count 0, failed_count 0,
    }
    string test_names = vec[string]()
    test_names = append(test_names, "emit_line")
    test_names = append(test_names, "register_allocate")
    test_names = append(test_names, "register_spillover")
    test_names = append(test_names, "stackframe_allocate")
    test_names = append(test_names, "stackframe_size")
    test_names = append(test_names, "instruction_select_mov")
    test_names = append(test_names, "instruction_select_add")
    test_names = append(test_names, "codegen_context_init")
    test_names = append(test_names, "multiple_functions")
    bool passed = false
    string message = ""
    passed, message = test_codegen_emit_line()
    suite.add_result("test_codegen_emit_line", passed, message)
    passed, message = test_register_allocate()
    suite.add_result("test_register_allocate", passed, message)
    passed, message = test_register_spillover()
    suite.add_result("test_register_spillover", passed, message)
    passed, message = test_stackframe_allocate()
    suite.add_result("test_stackframe_allocate", passed, message)
    passed, message = test_stackframe_size()
    suite.add_result("test_stackframe_size", passed, message)
    passed, message = test_instruction_select_mov()
    suite.add_result("test_instruction_select_mov", passed, message)
    passed, message = test_instruction_select_add()
    suite.add_result("test_instruction_select_add", passed, message)
    passed, message = test_codegen_context_init()
    suite.add_result("test_codegen_context_init", passed, message)
    passed, message = test_multiple_functions()
    suite.add_result("test_multiple_functions", passed, message)
    suite
}

func main() {
    test_suite suite = run_all_tests()
    suite.print_summary()
}
