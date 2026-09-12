package macos_driver

extern "intrinsic" func system(string cmd) int;
extern "intrinsic" func __host_read_to_string(string path) string;
extern "intrinsic" func __host_write_text_file(string path, string contents) int;

struct macos_config {
    string arch
    string os_version
    string deployment_target
    string sdk_path
    bool use_clang
}

struct macos_compiler {
    config macos_config
    string source_file
    string output_file
    string temp_dir
    string asm_file
    string obj_file
}

func macos_config_new() macos_config {
    return macos_config {
        arch: "arm64",
        os_version: "12.0.0",
        deployment_target: "12.0.0",
        sdk_path: "",
        use_clang: true,
    }
}

func macos_compiler_new(string source, string output) macos_compiler* {
    compiler := macos_compiler {
        config: macos_config_new(),
        source_file: source,
        output_file: output,
        temp_dir: "/tmp/s_macos_" + source,
        asm_file: "/tmp/s_macos_" + source + ".s",
        obj_file: "/tmp/s_macos_" + source + ".o",
    }
    return &compiler
}

func (c* macos_compiler) detect_architecture() string {

    arch_output := ""

    ret := system("uname -m > /tmp/s_arch_detect.txt")
    if ret == 0 {
        arch_output = __host_read_to_string("/tmp/s_arch_detect.txt")
    }

    if arch_output == "arm64" { return "arm64" }
    if arch_output == "x86_64" { return "x86_64" }

    return "arm64"
}

func (c* macos_compiler) detect_sdk_path() string {

    sdk_path := ""
    ret := system("xcrun --show-sdk-path > /tmp/s_sdk_path.txt 2>/dev/null")
    if ret == 0 {
        sdk_path = __host_read_to_string("/tmp/s_sdk_path.txt")
    }
    return sdk_path
}

func (c* macos_compiler) setup() {

    c.config.arch = c.detect_architecture()
    c.config.sdk_path = c.detect_sdk_path()
}

func (c* macos_compiler) generate_arm64_assembly() string {

    asm := ""
    asm = asm + ".section __TEXT,__text,regular,pure_instructions\n"
    asm = asm + ".global _main\n"
    asm = asm + ".p2align 2\n"
    asm = asm + "_main:\n"
    asm = asm + "    ; ARM64 entry point\n"
    asm = asm + "    stp x29, x30, [sp, #-16]!\n"
    asm = asm + "    mov x29, sp\n"
    asm = asm + "    mov x0, #0\n"
    asm = asm + "    ldp x29, x30, [sp], #16\n"
    asm = asm + "    ret\n"

    asm = asm + ".section __DATA,__data\n"
    asm = asm + ".section __TEXT,__cstring,cstring_literals\n"

    return asm
}

func (c* macos_compiler) generate_x86_64_assembly() string {

    asm := ""
    asm = asm + ".section __TEXT,__text,regular,pure_instructions\n"
    asm = asm + ".global _main\n"
    asm = asm + ".p2align 4,0x90\n"
    asm = asm + "_main:\n"
    asm = asm + "    ; x86_64 entry point\n"
    asm = asm + "    push rbp\n"
    asm = asm + "    mov rsp, rbp\n"
    asm = asm + "    xor eax, eax\n"
    asm = asm + "    pop rbp\n"
    asm = asm + "    ret\n"

    asm = asm + ".section __DATA,__data\n"
    asm = asm + ".section __TEXT,__cstring,cstring_literals\n"

    return asm
}

func (c* macos_compiler) compile_assembly_to_object() int {

    compiler := "clang"
    if !c.config.use_clang {
        compiler = "gcc"
    }

    cmd := compiler + " -c -arch " + c.config.arch

    if c.config.sdk_path != "" {
        cmd = cmd + " -isysroot " + c.config.sdk_path
    }

    cmd = cmd + " -mmacosx-version-min=" + c.config.deployment_target
    cmd = cmd + " -o " + c.obj_file
    cmd = cmd + " " + c.asm_file

    ret := system(cmd)
    return ret
}

func (c* macos_compiler) link_to_executable() int {

    linker := "clang"
    if !c.config.use_clang {
        linker = "gcc"
    }

    cmd := linker + " -arch " + c.config.arch

    if c.config.sdk_path != "" {
        cmd = cmd + " -isysroot " + c.config.sdk_path
    }

    cmd = cmd + " -mmacosx-version-min=" + c.config.deployment_target
    cmd = cmd + " -o " + c.output_file
    cmd = cmd + " " + c.obj_file

    ret := system(cmd)
    return ret
}

func (c* macos_compiler) compile() int {

    c.setup()

    asm := ""
    if c.config.arch == "arm64" {
        asm = c.generate_arm64_assembly()
    } else if c.config.arch == "x86_64" {
        asm = c.generate_x86_64_assembly()
    } else {
        return -1
    }

    write_ret := __host_write_text_file(c.asm_file, asm)
    if write_ret != 0 { return -1 }

    compile_ret := c.compile_assembly_to_object()
    if compile_ret != 0 { return -1 }

    link_ret := c.link_to_executable()
    if link_ret != 0 { return -1 }

    return 0
}

func macos_compile_file(string input, string output) int {

    compiler := macos_compiler_new(input, output)
    return compiler.compile()
}

func macos_compile_with_arch(string input, string output, string arch) int {

    compiler := macos_compiler_new(input, output)
    compiler.config.arch = arch
    return compiler.compile()
}