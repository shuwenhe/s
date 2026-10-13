package compile.compiler

import (
    "compile.internal.noder"
    "compile.internal.ir"
    "std.os"
)

func handle_compile_unit(string[] args) int {
    if len(args) < 4 {
        eprintln("usage: s_compiler --compile-unit <output.ir> <input.s>...")
        return 2
    }
    
    output_ir := args[2]
    input_files := vec[string]()
    
    for i := 3; i < len(args); i = i + 1 {
        input_files.push(args[i])
    }
    
    result := noder.load_package(input_files)
    
    switch result {
        result::ok(output) : {
            ir_content := ir.emit_ir(output.pkg)
            write_result := os.write_file(output_ir, ir_content)
            
            switch write_result {
                result::ok() : {
                    return 0
                }
                result::err(err_msg) : {
                    eprintln("compiler: cannot write IR: " + err_msg)
                    return 1
                }
            }
        }
        result::err(err_msg) : {
            eprintln("compiler: " + err_msg)
            return 1
        }
    }
}

func handle_emit_bin(string[] args) int {
    if len(args) != 4 {
        eprintln("usage: s_compiler --emit-bin <input.ir> <output>")
        return 2
    }
    
    ir_path := args[2]
    output_bin := args[3]
    
    ir_result := os.read_file(ir_path)
    
    switch ir_result {
        result::ok(ir_content) : {
            asm_result := ir.ir_to_asm(ir_content)
            
            switch asm_result {
                result::ok(asm_text) : {
                    temp_asm := output_bin + ".s"
                    write_asm_result := os.write_file(temp_asm, asm_text)
                    
                    switch write_asm_result {
                        result::ok() : {
                            return 0
                        }
                        result::err(err_msg) : {
                            eprintln("compiler: cannot write assembly: " + err_msg)
                            return 1
                        }
                    }
                }
                result::err(err_msg) : {
                    eprintln("compiler: ir to asm failed: " + err_msg)
                    return 1
                }
            }
        }
        result::err(err_msg) : {
            eprintln("compiler: cannot read IR: " + err_msg)
            return 1
        }
    }
}
