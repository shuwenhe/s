package test_backend

use backend

func test_codegen_basic() {
    builder := new_machine_code_builder()
    builder.emit_text_section()
    builder.emit_global_symbol("test_func")
    builder.emit_function_prologue("test_func")
    builder.emit_mov_immediate_to_register(42, "rax")
    builder.emit_function_epilogue()
    
    asm := builder.get_assembly()
    println("Generated Assembly:")
    println(asm)
}

func test_register_allocator() {
    allocator := new_register_allocator()
    
    r1 := allocator.allocate_for_variable("x")
    r2 := allocator.allocate_for_variable("y")
    r3 := allocator.allocate_for_variable("z")
    
    println("Register 1 (x): " + r1)
    println("Register 2 (y): " + r2)
    println("Register 3 (z): " + r3)
}

func test_stack_frame() {
    frame := new_stack_frame("main", 0)
    offset1 := frame.allocate_local("var1", 8)
    offset2 := frame.allocate_local("var2", 8)
    
    println("Variable 1 offset: " + offset1 as string)
    println("Variable 2 offset: " + offset2 as string)
    println("Total frame size: " + frame.get_frame_size() as string)
    println("Aligned size: " + frame.align_frame_size() as string)
}

func test_instruction_selector() {
    selector := new_instruction_selector()
    selector.select_mov_instruction("5", "x")
    selector.select_add_instruction("x", "3", "result")
    
    asm := selector.get_assembly()
    println("Selected Instructions:")
    println(asm)
}

func test_assembly_generator() {
    gen := new_assembly_generator()
    gen.emit_global_symbol("main")
    gen.emit_section("text")
    gen.emit_function_start("main")
    gen.emit_instruction("mov $42, %rax")
    gen.emit_instruction("ret")
    
    output := gen.get_output()
    println("Generated Assembly:")
    println(output)
}

func test_native_compiler_simple() {
    compiler := new_native_compiler("test.s", "test_output")
    result := compiler.compile_to_assembly()
    
    if result == 0 {
        println("✓ Assembly generation succeeded")
        asm := compiler.get_assembly()
        println(asm)
    } else {
        println("✗ Assembly generation failed")
    }
}

func main() {
    println("=== Backend Module Tests ===")
    println("")
    
    println("Test 1: Codegen Basic")
    test_codegen_basic()
    println("")
    
    println("Test 2: Register Allocator")
    test_register_allocator()
    println("")
    
    println("Test 3: Stack Frame")
    test_stack_frame()
    println("")
    
    println("Test 4: Instruction Selector")
    test_instruction_selector()
    println("")
    
    println("Test 5: Assembly Generator")
    test_assembly_generator()
    println("")
    
    println("Test 6: Native Compiler")
    test_native_compiler_simple()
    println("")
    
    println("=== All Tests Complete ===")
}
