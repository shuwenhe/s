package std.process
import (
    "std"
)
struct process {
    pid: int
    status: int
}

struct process_result {
    exit_code: int
    stdout: string
    stderr: string
}

func run_command(string cmd_line) (int, string) {
    argv := parse_command_line(cmd_line)
    if len(argv) == 0 {
        return -1, "empty command"
    }
    return -1, "process execution unavailable in native bootstrap"
}

func run_command_capture(string cmd_line) (int, string) {
    return -1, "process execution unavailable in native bootstrap"
}

func run_command_io(string cmd_line, string stdin_data) (int, string, string) {
    return -1, "", "process execution unavailable in native bootstrap"
}

func wait_for_process(int pid) int {
    return -1
}

func parse_command_line(string cmd_line) string[] {
    return string[]{}
}

func find_in_path(string program) (string, bool) {
    return "", false
}

func compile_to_ir(string compiler_bin, string source_file, string output_ir) (int, string) {
    cmd := compiler_bin + " " + source_file + " " + output_ir
    exit_code, err := run_command(cmd)
    if exit_code != 0 {
        return exit_code, "compilation failed: " + err
    }
    return 0, ""
}

func emit_ir_binary(string ir_codegen_bin, string input_ir, string output_bin) (int, string) {
    cmd := ir_codegen_bin + " --emit-bin " + input_ir + " -o " + output_bin
    exit_code, err := run_command(cmd)
    if exit_code != 0 {
        return exit_code, "emit failed: " + err
    }
    return 0, ""
}

func pipe_commands(string cmd1, string cmd2) (int, string) {
    return -1, "process execution unavailable in native bootstrap"
}
