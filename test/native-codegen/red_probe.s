package native_codegen_test

// Before the backend existed this API probe failed to compile because
// src/cmd/compile/internal/codegen/amd64_program.s was absent.
func main() int {
    program := function_ssa_program {
        package_name: "", entry_symbol: "", functions: function_ssa_function[](), calls: function_ssa_call[](),
    }
    result := emit_function_ssa_amd64(program)
    if result.error == "" || result.assembly != "" { return 1 }
    startup := amd64_executable_startup(program)
    if startup.error == "" || startup.assembly != "" { return 2 }
    return 0
}
