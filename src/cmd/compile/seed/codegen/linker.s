package seed.codegen
import (
    "std.process"
    "std.string"
)
struct compiler_toolchain {
    gcc_path: string
    ld_path: string
    as_path: string
}

func toolchain_create() compiler_toolchain {
    tc: compiler_toolchain
    tc.gcc_path = "gcc"
    tc.ld_path = "ld"
    tc.as_path = "as"
    tc
}

func (c* compiler_toolchain) assemble( asm_file string, string obj_file) (int, string) {
    cmd := tc.gcc_path + " -c " + asm_file + " -o " + obj_file
    exit_code, output := std.process.run_command(cmd)
    exit_code, output
}

func (c* compiler_toolchain) link_executable(string* obj_files[], string output) (int, string) {
    cmd := tc.gcc_path + " "
    for i < obj_files.len() {
        cmd = cmd + obj_files[i] + " "
    }
    cmd = cmd + "-o " + output
    exit_code, output := std.process.run_command(cmd)
    exit_code, output
}

func (c* compiler_toolchain) compile_to_executable( asm_file string, string obj_file, string output_exe) (int, string) {
    exit_code, msg := tc.assemble(asm_file, obj_file)
    if exit_code != 0 {
        return exit_code, "Assembly failed: " + msg
    }
    obj_files := vec[]()
    obj_files.push(obj_file)
    exit_code, msg = tc.link_executable(&obj_files, output_exe)
    if exit_code != 0 {
        return exit_code, "Linking failed: " + msg
    }
    0, ""
}

func (c* compiler_toolchain) add_stdlib_objects(string* obj_files[]) {
    obj_files.push("libc.so.6")
}
