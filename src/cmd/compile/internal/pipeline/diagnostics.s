package compile.internal.pipeline

struct diagnostic_message {
    string level  // "error", "warning", "info"
    string message
    string file
    int line
}

struct diagnostics {
    diagnostic_message[] messages
    int error_count
    int warning_count
}

func diagnostics_new() diagnostics {
    return diagnostics{
        messages: diagnostic_message[]{},
        error_count: 0,
        warning_count: 0,
    }
}

func add_error(diagnostics d, string message) {
    d.messages.append(diagnostic_message{
        level: "error",
        message: message,
    })
    d.error_count = d.error_count + 1
}

func add_warning(diagnostics d, string message) {
    d.messages.append(diagnostic_message{
        level: "warning",
        message: message,
    })
    d.warning_count = d.warning_count + 1
}
