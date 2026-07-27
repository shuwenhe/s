package std.process

use std.syscall
use std.io_syscall

struct Process {
    pid: int
    status: int  
}

struct ProcessResult {
    exit_code: int
    stdout: string
    stderr: string
}

func run_command(string cmd_line) (int, string) {

    let argv = parse_command_line(cmd_line)
    if len(argv) == 0 {
        return -1, "empty command"
    }

    let pid = syscall.fork()
    if pid < 0 {
        return pid, "fork failed"
    }

    if pid == 0 {

        let _ = syscall.execve(argv[0], argv, []string{})
        syscall.exit(127)  
    }

    let exit_code = wait_for_process(pid)
    return exit_code, ""
}

func run_command_capture(string cmd_line) (int, string) {

    0, ""
}

func run_command_io(string cmd_line, string stdin_data) (int, string, string) {

    0, "", ""
}

func wait_for_process(int pid) int {
    let status_ptr = 0
    let ret = syscall.waitpid(pid, status_ptr, 0)
    if ret < 0 {
        return ret
    }

    0
}

func parse_command_line(string cmd_line) []string {

    []string{}
}

func find_in_path(string program) (string, bool) {

    "", false
}

func compile_to_ir(string compiler_bin, string source_file, string output_ir) (int, string) {
    let cmd = compiler_bin + " " + source_file + " " + output_ir
    let exit_code, err = run_command(cmd)

    if exit_code != 0 {
        return exit_code, "compilation failed: " + err
    }

    return 0, ""
}

func emit_ir_binary(string ir_codegen_bin, string input_ir, string output_bin) (int, string) {
    let cmd = ir_codegen_bin + " --emit-bin " + input_ir + " -o " + output_bin
    let exit_code, err = run_command(cmd)

    if exit_code != 0 {
        return exit_code, "emit failed: " + err
    }

    return 0, ""
}

func pipe_commands(string cmd1, string cmd2) (int, string) {

    0, ""
}
