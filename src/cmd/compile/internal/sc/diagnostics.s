// Package: compile.internal.sc
// Module: diagnostics.s
// Description: Error handling, diagnostics, and panic recovery
// Corresponds to: Go cmd/compile/internal/base error handling

package compile.internal.sc

import (
    "std.io"
)

// Error severity levels
enum diagnostic_level {
    LEVEL_INFO = 0
    LEVEL_WARNING = 1
    LEVEL_ERROR = 2
    LEVEL_FATAL = 3
    LEVEL_INTERNAL_ERROR = 4
}

// Compilation error/warning
struct diagnostic_message {
    diagnostic_level level
    string filename
    int line
    int column
    string message
    string context  // Source code line for reference
    
    func is_error() bool {
        return level == diagnostic_level.LEVEL_ERROR || 
               level == diagnostic_level.LEVEL_FATAL ||
               level == diagnostic_level.LEVEL_INTERNAL_ERROR
    }
}

// Error context for debugging
struct error_context {
    string current_phase
    string current_function
    string current_file
    int error_count
    int warning_count
    diagnostic_message[] messages
}

// Panic recovery info
struct panic_info {
    string panic_message
    string backtrace
    error_context context
    bool recovered
}

// Initialize error context
func error_context_new() error_context {
    return error_context{
        current_phase: "initialization",
        current_function: "main",
        current_file: "",
        error_count: 0,
        warning_count: 0,
        messages: diagnostic_message[]{},
    }
}

// Report an error
func report_error(
    error_context ctx,
    string filename,
    int line,
    int column,
    string message
) {
    diag := diagnostic_message{
        level: diagnostic_level.LEVEL_ERROR,
        filename: filename,
        line: line,
        column: column,
        message: message,
        context: "",
    }
    
    ctx.messages.append(diag)
    ctx.error_count = ctx.error_count + 1
    
    print_diagnostic(diag)
}

// Report a warning
func report_warning(
    error_context ctx,
    string filename,
    int line,
    int column,
    string message
) {
    diag := diagnostic_message{
        level: diagnostic_level.LEVEL_WARNING,
        filename: filename,
        line: line,
        column: column,
        message: message,
        context: "",
    }
    
    ctx.messages.append(diag)
    ctx.warning_count = ctx.warning_count + 1
    
    print_diagnostic(diag)
}

// Report an internal compiler error
func report_internal_error(error_context ctx, string message) {
    diag := diagnostic_message{
        level: diagnostic_level.LEVEL_INTERNAL_ERROR,
        filename: ctx.current_file,
        line: 0,
        column: 0,
        message: message,
        context: "",
    }
    
    ctx.messages.append(diag)
    ctx.error_count = ctx.error_count + 1
    
    print_diagnostic(diag)
}

// Fatal error - stops compilation immediately
func fatal_error(error_context ctx, string message) {
    diag := diagnostic_message{
        level: diagnostic_level.LEVEL_FATAL,
        filename: ctx.current_file,
        line: 0,
        column: 0,
        message: message,
        context: "",
    }
    
    ctx.messages.append(diag)
    ctx.error_count = ctx.error_count + 1
    
    print_diagnostic(diag)
    
    // Exit immediately
    std.process.exit(2)
}

// Print a single diagnostic message
func print_diagnostic(diagnostic_message diag) {
    level_str := ""
    if diag.level == diagnostic_level.LEVEL_WARNING {
        level_str = "warning"
    } else if diag.level == diagnostic_level.LEVEL_ERROR {
        level_str = "error"
    } else if diag.level == diagnostic_level.LEVEL_FATAL {
        level_str = "fatal error"
    } else if diag.level == diagnostic_level.LEVEL_INTERNAL_ERROR {
        level_str = "internal compiler error"
    } else {
        level_str = "info"
    }
    
    location_str := ""
    if diag.filename != "" {
        location_str = diag.filename + ":"
        if diag.line > 0 {
            location_str = location_str + std.conv.fmt_int(diag.line) + ":"
            if diag.column > 0 {
                location_str = location_str + std.conv.fmt_int(diag.column) + ":"
            }
        }
        location_str = location_str + " "
    }
    
    std.io.eprintln(location_str + level_str + ": " + diag.message)
    
    if diag.context != "" {
        std.io.eprintln("  " + diag.context)
    }
}

// Print all accumulated error messages
func print_error_summary(error_context ctx) {
    if ctx.error_count == 0 && ctx.warning_count == 0 {
        return
    }
    
    std.io.eprintln("")
    
    if ctx.error_count > 0 {
        std.io.eprintln("Compilation failed with " + std.conv.fmt_int(ctx.error_count) + " error(s)")
    }
    
    if ctx.warning_count > 0 {
        std.io.eprintln("(" + std.conv.fmt_int(ctx.warning_count) + " warning(s))")
    }
}

// Set current compilation context for better error messages
func set_current_phase(error_context ctx, string phase_name) {
    ctx.current_phase = phase_name
    std.io.eprintln("[" + phase_name + "] Starting compilation phase")
}

func set_current_function(error_context ctx, string func_name) {
    ctx.current_function = func_name
}

func set_current_file(error_context ctx, string filename) {
    ctx.current_file = filename
}

// Check if compilation should continue
func should_continue_compilation(error_context ctx, int max_errors) bool {
    if ctx.error_count >= max_errors {
        std.io.eprintln("Compilation stopped after " + std.conv.fmt_int(max_errors) + " error(s)")
        return false
    }
    return true
}

// Panic recovery wrapper
func safe_execute(error_context ctx, string operation, func() void operation_func) bool {
    std.io.eprintln("[safety] Executing: " + operation)
    
    // TODO: Implement panic recovery when S language supports it
    // For now, just execute directly
    operation_func()
    
    return true
}

// Check for panics that occurred during compilation
func check_for_panics(error_context ctx) bool {
    // TODO: Check for any unhandled panics
    // Return true if panics were found
    return false
}

// Validate compilation state
func validate_compilation_state(error_context ctx) bool {
    if ctx.error_count > 0 {
        std.io.eprintln("Compilation aborted due to errors")
        return false
    }
    
    return true
}

// Format error for display with source context
func format_error_with_context(
    diagnostic_message diag,
    string source_line
) string {
    result := ""
    
    if diag.filename != "" {
        result = result + diag.filename + ":"
        if diag.line > 0 {
            result = result + std.conv.fmt_int(diag.line) + ":"
            if diag.column > 0 {
                result = result + std.conv.fmt_int(diag.column) + ":"
            }
        }
        result = result + " "
    }
    
    result = result + diag.message
    
    if source_line != "" {
        result = result + "\n  " + source_line
        if diag.column > 0 {
            // Add pointer to error location
            i := 0
            while i < diag.column - 1 {
                result = result + " "
                i = i + 1
            }
            result = result + "^"
        }
    }
    
    return result
}
