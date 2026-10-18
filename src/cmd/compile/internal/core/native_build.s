package compile.internal.core

import (
    "compile.internal.compiler"
    "compile.internal.mir"
    "compile.internal.ssa"
    "compile.internal.codegen"
)

// Host tool boundary only. These primitives never execute the input S program.
// Native applications contain the selected instructions and Linux startup only.
extern "intrinsic" func __host_run_argv(string[] args) int
extern "intrinsic" func __host_same_file(string left, string right) bool
extern "intrinsic" func __host_rename_file(string from, string to) int
extern "intrinsic" func __host_make_temp_dir_in(string directory) string
extern "intrinsic" func __host_read_source(string path) string

func native_target_supported() bool {
    return runtime_env_get("S_TARGET_OS", "linux") == "linux" && runtime_env_get("S_TARGET_ARCH", "amd64") == "amd64"
}

func native_program_assembly(mir_program program, bool executable) amd64_program_result {
    lowered := lower_function_mir_to_ssa(program)
    if lowered.error != "" { return amd64_program_result { assembly: "", error: lowered.error } }
    emitted := emit_function_ssa_amd64(lowered.program)
    if emitted.error != "" { return emitted }
    if executable {
        startup := amd64_executable_startup(lowered.program)
        if startup.error != "" { return startup }
        return amd64_program_result { assembly: emitted.assembly + startup.assembly, error: "" }
    }
    return emitted
}

func native_emit_asm_file(string input, string output, bool executable) int {
    if !native_target_supported() { eprintln("native compiler: P0 supports Linux/amd64"); return 2 }
    if input == output || __host_same_file(input, output) {
        eprintln("native compiler: output must not overwrite input source")
        return 2
    }
    source := __host_read_source(input)
    if source == "" { eprintln("native compiler: empty or unreadable input"); return 1 }
    mirrored := native_source_to_mir(source)
    if mirrored.error != "" { eprintln(mirrored.error); return 1 }
    emitted := native_program_assembly(mirrored.program, executable)
    if emitted.error != "" { eprintln(emitted.error); return 1 }
    if __host_write_text_file(output, emitted.assembly) != 0 {
        eprintln("native compiler: cannot write assembly: " + output)
        return 1
    }
    return 0
}

func native_output_directory(string output) string {
    last := -1
    i := 0
    for i < len(output) {
        if __host_char_at(output, i) == "/" { last = i }
        i = i + 1
    }
    if last < 0 { return "." }
    if last == 0 { return "/" }
    return __host_slice(output, 0, last)
}

func native_remove_temporary(string directory) int {
    return __host_run_argv(["rm", "-rf", "--", directory])
}

func native_install_program(mir_program program, string input, string output, string ssa_margin_override, bool executable) int {
    if output == "" || input == output || __host_same_file(input, output) {
        eprintln("native compiler: output must not overwrite input source")
        return 2
    }
    if !native_target_supported() {
        eprintln("native compiler: P0 supports Linux/amd64")
        return 2
    }
    if ssa_margin_override != "" {
        eprintln("native compiler: SSA tuning overrides are not supported in P0")
        return 2
    }
    emitted := native_program_assembly(program, executable)
    if emitted.error != "" { eprintln(emitted.error); return 1 }
    directory := native_output_directory(output)
    if __host_run_argv(["mkdir", "-p", "--", directory]) != 0 {
        eprintln("native compiler: cannot create output directory")
        return 1
    }
    temporary := __host_make_temp_dir_in(directory)
    if temporary == "" { eprintln("native compiler: cannot create temporary directory"); return 1 }
    assembly_path := temporary + "/program.s"
    object_path := temporary + "/program.o"
    binary_path := temporary + "/program"
    if __host_write_text_file(assembly_path, emitted.assembly) != 0 {
        native_remove_temporary(temporary)
        eprintln("native compiler: cannot write temporary assembly")
        return 1
    }
    assembler := runtime_env_get("S_AS", "as")
    if __host_run_argv([assembler, "--64", "-o", object_path, assembly_path]) != 0 {
        native_remove_temporary(temporary)
        eprintln("native compiler: assembler failed")
        return 1
    }
    final_path := object_path
    if executable {
        linker := runtime_env_get("S_LD", "ld")
        if __host_run_argv([linker, "-m", "elf_x86_64", "-nostdlib", "-o", binary_path, object_path]) != 0 {
            native_remove_temporary(temporary)
            eprintln("native compiler: linker failed")
            return 1
        }
        final_path = binary_path
    }
    // The temporary artifact shares the destination filesystem. Install only
    // after every stage succeeds; failed compilation leaves prior output intact.
    if __host_rename_file(final_path, output) != 0 {
        native_remove_temporary(temporary)
        eprintln("native compiler: cannot install executable: " + output)
        return 1
    }
    native_remove_temporary(temporary)
    eprintln("native-codegen=structured-mir-to-ssa-to-amd64")
    return 0
}

func native_build_program(mir_program program, string input, string output, string ssa_margin_override, bool nostdlib) int {
    // P0 executable startup is always libc-free, including without nostdlib.
    return native_install_program(program, input, output, ssa_margin_override, true)
}

func native_build_object_program(mir_program program, string input, string output, string ssa_margin_override) int {
    return native_install_program(program, input, output, ssa_margin_override, false)
}

func native_build_object(string input, string output) int {
    if input == output || __host_same_file(input, output) {
        eprintln("native compiler: output must not overwrite input source")
        return 2
    }
    source := __host_read_source(input)
    if source == "" { eprintln("native compiler: empty or unreadable input"); return 1 }
    mirrored := native_source_to_mir(source)
    if mirrored.error != "" { eprintln(mirrored.error); return 1 }
    return native_build_object_program(mirrored.program, input, output, "")
}

func native_build(string input, string output, string ssa_margin_override, bool nostdlib) int {
    if input == output || __host_same_file(input, output) {
        eprintln("native compiler: output must not overwrite input source")
        return 2
    }
    source := __host_read_source(input)
    if source == "" { eprintln("native compiler: empty or unreadable input"); return 1 }
    mirrored := native_source_to_mir(source)
    if mirrored.error != "" { eprintln(mirrored.error); return 1 }
    return native_build_program(mirrored.program, input, output, ssa_margin_override, nostdlib)
}
