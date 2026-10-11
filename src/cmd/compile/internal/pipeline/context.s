package compile.internal.pipeline

struct compilation_context {
    string source_root
    string host_os
    string host_arch
    string target_os
    string target_arch
    string input_file
    string output_file
    bool verbose
    bool debug_mode
}

func context_new(string input, string output) compilation_context {
    return compilation_context{
        input_file: input,
        output_file: output,
        verbose: false,
        debug_mode: false,
    }
}
