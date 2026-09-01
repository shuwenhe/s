package backend

struct compiler_pipeline {
    direct_code_generator* codegen
    prog_list* all_code
}

func make_compiler_pipeline() compiler_pipeline {
    pipeline: compiler_pipeline
    pipeline.codegen = &make_direct_code_generator()
    pipeline.all_code = &make_prog_list()
    pipeline
}

func (cp* compiler_pipeline) compile_simple_function() string {
    cp.codegen.generate_function_prologue("add", 0)
    
    cp.codegen.emit_const_i64(10, 0)
    cp.codegen.emit_const_i64(20, 1)
    cp.codegen.emit_add_i64(0, 1, 0)
    
    cp.codegen.generate_function_epilogue()
    
    cp.codegen.get_asm()
}

func (cp* compiler_pipeline) compile_with_stack() string {
    stack_size := 32
    cp.codegen.generate_function_prologue("compute", stack_size)
    
    cp.codegen.emit_const_i64(42, 0)
    cp.codegen.main_code.append_prog(prog_op_store(), "\tmovq\t%rax, -8(%rbp)")
    
    cp.codegen.generate_function_epilogue()
    
    cp.codegen.get_asm()
}

func (cp* compiler_pipeline) compile_branching() string {
    cp.codegen.generate_function_prologue("branching", 0)
    
    cp.codegen.emit_const_i64(5, 0)
    
    label1 := "L1"
    cp.codegen.main_code.append_prog(prog_op_cmp(), "\tcmpq\t$0, %rax")
    cp.codegen.main_code.append_prog(prog_op_je(), "\tje\t" + label1)
    
    cp.codegen.emit_const_i64(1, 0)
    
    label2 := "L2"
    cp.codegen.main_code.append_prog(prog_op_jmp(), "\tjmp\t" + label2)
    
    cp.codegen.main_code.append_prog(20, label1 + ":")
    cp.codegen.emit_const_i64(0, 0)
    
    cp.codegen.main_code.append_prog(20, label2 + ":")
    cp.codegen.generate_function_epilogue()
    
    cp.codegen.get_asm()
}

func (cp* compiler_pipeline) compile_loop() string {
    cp.codegen.generate_function_prologue("loop_func", 0)
    
    cp.codegen.emit_const_i64(0, 0)
    
    loop_start := "L_loop_start"
    loop_end := "L_loop_end"
    
    cp.codegen.main_code.append_prog(20, loop_start + ":")
    
    cp.codegen.main_code.append_prog(prog_op_cmp(), "\tcmpq\t$10, %rax")
    cp.codegen.main_code.append_prog(prog_op_jmp(), "\tjge\t" + loop_end)
    
    cp.codegen.emit_const_i64(1, 1)
    cp.codegen.emit_add_i64(0, 1, 0)
    
    cp.codegen.main_code.append_prog(prog_op_jmp(), "\tjmp\t" + loop_start)
    
    cp.codegen.main_code.append_prog(20, loop_end + ":")
    cp.codegen.generate_function_epilogue()
    
    cp.codegen.get_asm()
}

func (cp* compiler_pipeline) compile_multiple_functions() string {
    result := ".intel_syntax noprefix\n"
    result = result + ".section\t.text\n"
    
    cp.codegen.generate_function_prologue("func1", 0)
    cp.codegen.emit_const_i64(42, 0)
    cp.codegen.generate_function_epilogue()
    
    cp.codegen.generate_function_prologue("func2", 0)
    cp.codegen.emit_const_i64(100, 0)
    cp.codegen.generate_function_epilogue()
    
    p := cp.codegen.main_code.first()
    while p != nil {
        result = result + p.as_string + "\n"
        p = p.next
    }
    
    result
}
