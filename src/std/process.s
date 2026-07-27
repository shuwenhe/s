package std.process

use std.syscall
use std.io_syscall

// Process execution (pure syscall-based)
// Spawns child processes and captures output

struct Process {
    pid: int
    status: int  // 0 = running, else = exit code
}

struct ProcessResult {
    exit_code: int
    stdout: string
    stderr: string
}

// === Process Spawning ===

// Run command and wait for exit (simple version)
// Syntax: run_command("echo hello") or run_command("gcc -c foo.s")
func run_command(string cmd_line) (int, string) {
    // Parse command line into argv
    let argv = parse_command_line(cmd_line)
    if len(argv) == 0 {
        return -1, "empty command"
    }
    
    // Fork child process
    let pid = syscall.fork()
    if pid < 0 {
        return pid, "fork failed"
    }
    
    if pid == 0 {
        // Child process: exec the command
        let _ = syscall.execve(argv[0], argv, []string{})
        syscall.exit(127)  // If exec fails
    }
    
    // Parent: wait for child
    let exit_code = wait_for_process(pid)
    return exit_code, ""
}

// Run command and capture stdout
func run_command_capture(string cmd_line) (int, string) {
    // This requires pipe() support
    // TODO: 
    // 1. Create pipe for stdout
    // 2. Fork child
    // 3. Redirect child's stdout to pipe
    // 4. Parent reads from pipe
    // 5. Wait for child
    
    0, ""
}

// Run command with stdin, stdout, stderr redirection
func run_command_io(string cmd_line, string stdin_data) (int, string, string) {
    // TODO: Full I/O redirection support
    0, "", ""
}

// === Process Wait ===

// Wait for process to exit, return exit code
func wait_for_process(int pid) int {
    let status_ptr = 0
    let ret = syscall.waitpid(pid, status_ptr, 0)
    if ret < 0 {
        return ret
    }
    
    // Extract exit code from status
    // TODO: Parse status properly
    0
}

// === Utilities ===

// Parse command line into argv array
// "gcc -c foo.s -o foo.o" → ["gcc", "-c", "foo.s", "-o", "foo.o"]
func parse_command_line(string cmd_line) []string {
    // TODO: Implement shell-like parsing
    // Handle quotes, escapes, etc.
    []string{}
}

// Find executable in PATH
func find_in_path(string program) (string, bool) {
    // TODO: Search PATH environment variable
    "", false
}

// === High-level Wrapper ===

// Compile S source file to IR using seed compiler
// Returns: (exit_code, error_message)
func compile_to_ir(string compiler_bin, string source_file, string output_ir) (int, string) {
    let cmd = compiler_bin + " " + source_file + " " + output_ir
    let exit_code, err = run_command(cmd)
    
    if exit_code != 0 {
        return exit_code, "compilation failed: " + err
    }
    
    return 0, ""
}

// Emit IR to native binary using IR codegen
func emit_ir_binary(string ir_codegen_bin, string input_ir, string output_bin) (int, string) {
    let cmd = ir_codegen_bin + " --emit-bin " + input_ir + " -o " + output_bin
    let exit_code, err = run_command(cmd)
    
    if exit_code != 0 {
        return exit_code, "emit failed: " + err
    }
    
    return 0, ""
}

// === Piping Support (Advanced) ===

// Pipe one command's output to another
// pipe_commands("gcc -E foo.s", "s-preprocess") 
func pipe_commands(string cmd1, string cmd2) (int, string) {
    // TODO: Implement pipe(2) + fork + dup2
    0, ""
}
