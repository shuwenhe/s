package backend
struct backend_context {
    compiler: native_compiler
    native_enabled: bool
    target_arch: string
    target_os: string
}

func new_backend_context(string input, string output, bool native) backend_context {
    ctx: backend_context
    ctx.compiler = new_native_compiler(input, output)
    ctx.native_enabled = native
    ctx.target_arch = "x86_64"
    ctx.target_os = "linux"
    ctx
}

func (backend_context* bc) compile_native() int {
    if !bc.native_enabled {
        return -1
    }
    result := bc.compiler.compile_to_assembly()
    if result != 0 {
        return result
    }
    result = bc.compiler.assemble_to_object()
    if result != 0 {
        return result
    }
    result = bc.compiler.link_to_executable()
    if result != 0 {
        return result
    }
    0
}

func (backend_context* bc) get_assembly_output() string {
    bc.compiler.get_assembly()
}
