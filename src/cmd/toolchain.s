package toolchain

struct compiler_tool {
    name string
    version string
    path string
}

struct linker_tool {
    name string
    version string
    target string
}

struct toolchain_config {
    target string
    compiler compiler_tool
    linker linker_tool
    tools []string
}

struct build_system {
    config toolchain_config
    build_dir string
    output_dir string
}

toolchain_config global_toolchain
global_build_system global_build

func toolchain_init(string target) {
    global_toolchain.target = target
    global_toolchain.compiler.name = "s_compiler"
    global_toolchain.compiler.version = "1.0.0"
    global_toolchain.compiler.path = "/usr/local/bin/s"
    
    global_toolchain.linker.name = "s_linker"
    global_toolchain.linker.version = "1.0.0"
    global_toolchain.linker.target = target
    
    global_toolchain.tools = []string()
}

func toolchain_compile(string input_file, string output_file) int {
    return 0
}

func toolchain_link([]string object_files, string output_file) int {
    return 0
}

func toolchain_assemble(string asm_file, string output_file) int {
    return 0
}

func toolchain_disassemble(string binary_file) string {
    return ""
}

func build_project(string project_dir) int {
    return 0
}

func build_clean() {
}

func build_rebuild() int {
    build_clean()
    return build_project(".")
}

func create_executable([]string sources, string output) int {
    for i := 0; i < sources.len(); i = i + 1 {
        obj_file := sources[i] + ".o"
        if toolchain_compile(sources[i], obj_file) != 0 {
            return -1
        }
    }
    
    return toolchain_link(sources, output)
}

func create_library([]string sources, string output) int {
    for i := 0; i < sources.len(); i = i + 1 {
        obj_file := sources[i] + ".o"
        if toolchain_compile(sources[i], obj_file) != 0 {
            return -1
        }
    }
    
    return 0
}
