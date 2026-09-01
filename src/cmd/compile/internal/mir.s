package compile.internal.mir
use compile.internal.borrow.analyze_function as analyze_borrow_function
use s.block_expr
use s.function_decl
use s.dump_expr
use s.dump_stmt
use std.option.option
use std.prelude.to_string
use std.slices
struct mir_operand {
    string kind
    string value
    string type_name
}

struct mir_local_slot {
    int id
    string name
    string kind
    int version
    string type_name
    bool copyable
}

struct mir_assign_stmt {
    int target
    string op
    string[] args
}

struct mir_eval_stmt {
    string op
    string[] args
}

struct mir_move_stmt {
    int target
    mir_operand source
}

struct mir_copy_stmt {
    int target
    mir_operand source
}

struct mir_drop_stmt {
    int slot
}
enum mir_statement {
    assign(mir_assign_stmt),
    eval(mir_eval_stmt),
    move(mir_move_stmt),
    copy(mir_copy_stmt),
    drop(mir_drop_stmt),
}

struct mir_control_edge {
    string label
    int target
    mir_operand[] args
}

struct mir_terminator {
    string kind
    mir_control_edge[] edges
}

struct mir_basic_block {
    int id
    string label
    mir_statement[] statements
    mir_terminator terminator
}

struct mir_graph {
    string function_name
    mir_basic_block[] blocks
    mir_local_slot[] locals
    string[] trace
    int entry
    int exit
}

func lower_function_graph(function_decl function) mir_graph {
    if function.body.is_some() {
        return lower_block_graph(function.sig.name, function.body.unwrap())
    }
    empty_statements := mir_statement[]()
    empty_edges := mir_control_edge[]()
    blocks := mir_basic_block[]()
    blocks.push(mir_basic_block {
        id: 0,
        label: "entry",
        statements: empty_statements,
        terminator: mir_terminator {
            kind: "return",
            edges: empty_edges,
        },
    })
    trace := string[]()
    trace = append(trace, "block |   yield unit")
    mir_graph {
        function_name: function.sig.name,
        blocks: blocks,
        locals: mir_local_slot[](),
        trace: trace,
        entry: 0,
        exit: 0,
    }
}

func lower_block_graph(string function_name, block_expr block) mir_graph {
    statements := mir_statement[]()
    index := 0
    for index < len(block.statements) {
        stmt_text := join_text(dump_stmt(block.statements[index], indent(1)), " | ")
        args := string[]()
        args = append(args, stmt_text)
        statements.push(mir_statement::eval(mir_eval_stmt {
            op: "stmt",
            args: args,
        }))
        index = index + 1
    }
    trace := string[]()
    trace_text := "block"
    index = 0
    for index < len(block.statements) {
        stmt_trace := join_text(dump_stmt(block.statements[index], indent(1)), " | ")
        trace_text = trace_text + " | " + indent(1) + stmt_trace
        index = index + 1
    }
    if block.final_expr.is_some() {
        trace_text = trace_text + " | " + indent(1) + "yield " + dump_expr(block.final_expr.unwrap())
    } else {
        trace_text = trace_text + " | " + indent(1) + "yield unit"
    }
    trace = append(trace, trace_text)
    blocks := mir_basic_block[]()
    blocks.push(mir_basic_block {
        id: 0,
        label: "entry",
        statements: statements,
        terminator: mir_terminator {
            kind: "return",
            edges: mir_control_edge[](),
        },
    })
    mir_graph {
        function_name: function_name,
        blocks: blocks,
        locals: mir_local_slot[](),
        trace: trace,
        entry: 0,
        exit: 0,
    }
}

func dump_graph(mir_graph graph) string {
    out := "mir " + graph.function_name
        + " blocks=" + to_string(len(graph.blocks))
        + " entry=" + to_string(graph.entry)
        + " exit=" + to_string(graph.exit)
    i := 0
    for i < len(graph.blocks) {
        block := graph.blocks[i]
        out = out + " | bb" + to_string(block.id)
            + "(" + block.label + ")"
            + " stmts=" + to_string(len(block.statements))
            + " term=" + block.terminator.kind
        i = i + 1
    }
    out
}

func block_count(mir_graph graph) int {
    len(graph.blocks)
}

func lower_function(function_decl function) string {
    graph := lower_function_graph(function)
    return analyze_borrow_function(function.sig.name, string[](), dump_graph(graph))
}

func lower_block(block_expr block) string {
    text := "block"
    index := 0
    for index < len(block.statements) {
        stmt_text := join_text(dump_stmt(block.statements[index], indent(1)), " | ")
        text = text + " | " + indent(1) + stmt_text
        index = index + 1
    }
    if block.final_expr.is_some() {
        tail := block.final_expr.unwrap()
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

func indent(int depth) string {
    out := ""
    i := 0
    for i < depth {
        out = out + "  "
        i = i + 1
    }
    return out
}

func join_text(string[] values, string sep) string {
    out := ""
    i := 0
    for i < len(values) {
        if i > 0 {
            out = out + sep
        }
        out = out + values[i]
        i = i + 1
    }
    return out
}
