package compile.internal.noder
use s.source_file
use std.option.option
use std.result.result
use std.slices

struct noder_error {
    string code
    string message
    string path
    int line
    int column
}

struct source_unit {
    string path
    string text
}

struct token_item {
    string kind
    string text
    int line
    int column
}

struct import_record {
    string path
    option[string] alias
}

struct export_record {
    string name
    string kind
}

struct pos_entry {
    int offset
    int line
    int column
}

struct ir_node {
    string op
    string payload
}

struct noder_output {
    source_unit unit
    token_item[] tokens
    import_record[] imports
    source_file ast
    ir_node[] ir
    export_record[] exports
    string[] notes
}

func ok_error() noder_error {
    noder_error {
        code: "",
        message: "",
        path: "",
        line: 0,
        column: 0,
    }
}

func make_error(string code, string message, string path, int line, int column) noder_error {
    noder_error {
        code: code,
        message: message,
        path: path,
        line: line,
        column: column,
    }
}

func ok_unit(string path, string text) (source_unit, noder_error) {
    source_unit {
        path: path,
        text: text,
    }
}

func err_unit(string code, string message, string path, int line, int column) (source_unit, noder_error) {
    make_error(code, message, path, line, column)
}
