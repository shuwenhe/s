package compile.internal.ssa_core

use std.prelude.char_at
use std.prelude.len
use std.prelude.slice
use std.prelude.to_string
use std.vec.vec

struct ssa_program {
    string function_name,
    int32 block_count,
    int32 value_count,
    vec[string] allocated_regs,
}

func build_pipeline(string mir_text, string goarch) ssa_program {
    var function_name = parse_function_name(mir_text)
    var block_count = parse_int_after(mir_text, "blocks=")
    var value_count = count_token(mir_text, " stmts=")
    if value_count == 0 {
        value_count = block_count
    }

    ssa_program {
        function_name: function_name,
        block_count: block_count,
        value_count: value_count,
        allocated_regs: linear_scan_regalloc(value_count, goarch),
    }
}

func linear_scan_regalloc(int32 value_count, string goarch) vec[string] {
    var regs = register_bank(goarch)
    if regs.len() == 0 {
        return vec[string]()
    }

    var out = vec[string]()
    var i = 0
    while i < value_count {
        var reg_index = i
        while reg_index >= regs.len() {
            reg_index = reg_index - regs.len()
        }
        out.push(regs[reg_index])
        i = i + 1
    }

    out
}

func register_bank(string goarch) vec[string] {
    var regs = vec[string]()
    if goarch == "arm64" {
        regs.push("x9")
        regs.push("x10")
        regs.push("x11")
        regs.push("x12")
        regs.push("x13")
        regs.push("x14")
        regs.push("x15")
        return regs
    }

    regs.push("r10")
    regs.push("r11")
    regs.push("r12")
    regs.push("r13")
    regs.push("r14")
    regs.push("r15")
    regs
}

func parse_function_name(string mir_text) string {
    if !starts_with(mir_text, "mir ") {
        return "main"
    }
    var begin = 4
    var end = find_token(mir_text, " blocks=")
    if end <= begin {
        return "main"
    }
    slice(mir_text, begin, end)
}

func parse_int_after(string text, string marker) int32 {
    var start = find_token(text, marker)
    if start > text.len() {
        return 0
    }
    start = start + marker.len()
    var value = 0
    var i = start
    while i < text.len() && is_digit(char_at(text, i)) {
        var ch = char_at(text, i)
        value = value * 10 + parse_digit(ch)
        i = i + 1
    }
    value
}

func count_token(string text, string token) int32 {
    var total = 0
    var i = 0
    while i <= text.len() - token.len() {
        if slice(text, i, i + token.len()) == token {
            total = total + 1
            i = i + token.len()
        } else {
            i = i + 1
        }
    }
    total
}

func dump_pipeline(ssa_program program) string {
    var out = "ssa " + program.function_name
        + " blocks=" + to_string(program.block_count)
        + " values=" + to_string(program.value_count)

    var i = 0
    while i < program.allocated_regs.len() {
        out = out + " | v" + to_string(i) + "->" + program.allocated_regs[i]
        i = i + 1
    }

    out
}

func parse_digit(string ch) int32 {
    if ch == "0" { return 0 }
    if ch == "1" { return 1 }
    if ch == "2" { return 2 }
    if ch == "3" { return 3 }
    if ch == "4" { return 4 }
    if ch == "5" { return 5 }
    if ch == "6" { return 6 }
    if ch == "7" { return 7 }
    if ch == "8" { return 8 }
    if ch == "9" { return 9 }
    0
}

func is_digit(string ch) bool {
    ch >= "0" && ch <= "9"
}

func find_token(string text, string token) int32 {
    if token == "" {
        return 0
    }
    if text.len() < token.len() {
        return text.len() + 1
    }

    var i = 0
    while i <= text.len() - token.len() {
        if slice(text, i, i + token.len()) == token {
            return i
        }
        i = i + 1
    }
    text.len() + 1
}

func starts_with(string text, string prefix) bool {
    if text.len() < prefix.len() {
        return false
    }
    slice(text, 0, prefix.len()) == prefix
}