package compile.internal.noder
use s.source_file
use std.option.option
use std.result.result
use std.slices
struct noder_error {
    code string
    message string
    path string
    line int
    column int
}

struct source_unit {
    path string
    text string
}

struct token_item {
    kind string
    text string
    line int
    column int
}

struct import_record {
    path string
    option[string] alias
}

struct export_record {
    name string
    kind string
}

struct pos_entry {
    offset int
    line int
    column int
}

struct ir_node {
    op string
    payload string
}

struct noder_output {
    unit source_unit
    token_item[] tokens
    import_record[] imports
    ast source_file
    ir_node[] ir
    export_record[] exports
    string[] notes
}

func ok_error() noder_error {
    noder_error {
        code: "",
        message: "",
        path: "", line 0, column 0,
    }
}

func make_error(string code, string message, string path, int line, int column) noder_error {
    noder_error {
        code: code, message message, path path, line line, column column,
    }
}

func ok_unit(string path, string text) (source_unit, noder_error) {
    source_unit {
        path: path, text text,
    }
}

func err_unit(string code, string message, string path, int line, int column) (source_unit, noder_error) {
    make_error(code, message, path, line, column)
}