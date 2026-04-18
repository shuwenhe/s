package compile.internal.mir

use compile.internal.borrow.analyze_function as analyze_borrow_function
use s.block_expr
use s.function_decl
use s.dump_expr
use s.dump_stmt
use std.option.Option
use std.vec.Vec

struct mir_operand {
    string kind,
    string value,
    string type_name,
}

struct mir_local_slot {
    int32 id,
    string name,
    string kind,
    int32 version,
    string type_name,
    bool copyable,
}

struct mir_assign_stmt {
    int32 target,
    string op,
    Vec[string] args,
}

struct mir_eval_stmt {
    string op,
    Vec[string] args,
}

struct mir_move_stmt {
    int32 target,
    mir_operand source,
}

struct mir_copy_stmt {
    int32 target,
    mir_operand source,
}

struct mir_drop_stmt {
    int32 slot,
}

enum mir_statement {
    Assign(mir_assign_stmt),
    Eval(mir_eval_stmt),
    Move(mir_move_stmt),
    Copy(mir_copy_stmt),
    Drop(mir_drop_stmt),
}

struct mir_control_edge {
    string label,
    int32 target,
    Vec[mir_operand] args,
}

struct mir_terminator {
    string kind,
    Vec[mir_control_edge] edges,
}

struct mir_basic_block {
    int32 id,
    string label,
    Vec[mir_statement] statements,
    mir_terminator terminator,
}

struct mir_graph {
    Vec[string] blocks,
    Vec[string] locals,
    Vec[string] trace,
    int32 entry,
    int32 exit,
}

func lower_function(function_decl function) string {
    if function.body.is_some() {
        var body = function.body.unwrap()
        return analyze_borrow_function(function.sig.name, Vec[string](), lower_block(body))
    }
    return analyze_borrow_function(function.sig.name, Vec[string](), "")
}

func lower_block(block_expr block) string {
    var text = "block"

    var index = 0
    while index < block.statements.len() {
        var stmt_text = join_text(dump_stmt(block.statements[index], indent(1)), " | ")
        text = text + " | " + indent(1) + stmt_text
        index = index + 1
    }

    if block.final_expr.is_some() {
        var tail = block.final_expr.unwrap()
        return text + " | " + indent(1) + "yield " + dump_expr(tail)
    } else {
        return text + " | " + indent(1) + "yield unit"
    }
}

func trace_branch(string condition_text, string then_text, string else_text) string {
    if else_text == "" {
        return "branch " + condition_text + " | " + indent(1) + "then " + then_text + " | " + indent(1) + "else <missing>"
    }
    return "branch " + condition_text + " | " + indent(1) + "then " + then_text + " | " + indent(1) + "else " + else_text
}

func trace_loop(string loop_kind, string condition_text, string body_text) string {
    return loop_kind + " " + condition_text + " | " + indent(1) + "body " + body_text
}

func trace_switch(string subject_text, string arms_text) string {
    if arms_text == "" {
        return "switch " + subject_text
    }
    return "switch " + subject_text + " | " + arms_text
}

func indent(int32 depth) string {
    var out = ""
    var i = 0
    while i < depth {
        out = out + "  "
        i = i + 1
    }
    return out
}

func join_text(Vec[string] values, string sep) string {
    var out = ""
    var i = 0
    while i < values.len() {
        if i > 0 {
            out = out + sep
        }
        out = out + values[i]
        i = i + 1
    }
    return out
}
