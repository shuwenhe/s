package compile.internal.mir
use compile.internal.borrow.borrow_check_events
use compile.internal.borrow.analyze_function as analyze_borrow_function
use compile.internal.typesys.is_copy_type
use s.block_expr
use s.function_decl
use s.param
use s.expr
use s.stmt
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
    bool borrow_ok
    int borrow_errors
    string borrow_message
}

func lower_function_graph(function_decl function) mir_graph {
    if function.body.is_some() {
        return lower_block_graph(function.sig.name, function.sig.params, function.body.unwrap())
    }
    empty_statements := mir_statement[]()
    empty_edges := mir_control_edge[]()
    blocks := mir_basic_block[]()
    blocks.push(mir_basic_block {
        id: 0,
        label: "entry", statements empty_statements, terminator mir_terminator {
            kind: "return", edges empty_edges,
        },
    })
    trace := string[]()
    trace = append(trace, "block |   yield unit")
    mir_graph {
        function_name: function.sig.name, blocks blocks, locals mir_local_slot[](), trace trace, entry 0, exit 0,
        borrow_ok: true, borrow_errors: 0, borrow_message: "",
    }
}

func lower_block_graph(string function_name, param[] params, block_expr block) mir_graph {
    locals := mir_collect_locals(params, block)
    statements := mir_statement[]()
    events := string[]()
    local_index := 0
    for local_index < len(locals) {
        events = append(events, "declare:" + locals[local_index].name)
        local_index = local_index + 1
    }
    index := 0
    for index < len(block.statements) {
        stmt_text := join_text(dump_stmt(block.statements[index], indent(1)), " | ")
        args := string[]()
        args = append(args, stmt_text)
        statements.push(mir_statement::eval(mir_eval_stmt {
            op: "stmt", args args,
        }))
        events = mir_extend_events(events, mir_stmt_events(block.statements[index], locals))
        index = index + 1
    }
    if block.final_expr.is_some() {
        events = mir_extend_events(events, mir_expr_events(block.final_expr.unwrap(), locals, true))
    }
    mir_append_scope_drops(locals, statements, events)
    borrow_result := borrow_check_events(events)
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
        label: "entry", statements statements, terminator mir_terminator {
            kind: "return", edges mir_control_edge[](),
        },
    })
    mir_graph {
        function_name: function_name, blocks blocks, locals locals, trace trace, entry 0, exit 0,
        borrow_ok: borrow_result.ok, borrow_errors: borrow_result.errors, borrow_message: borrow_result.message,
    }
}

func mir_find_local(mir_local_slot[] locals, string name) int {
    i := 0
    for i < len(locals) {
        if locals[i].name == name { return i }
        i = i + 1
    }
    -1
}

func mir_type_is_copy(string type_name) bool {
    is_copy_type(type_name)
}

func mir_append_scope_drops(mir_local_slot[] locals, mir_statement[] statements, string[] events) () {
    i := len(locals) - 1
    for i >= 0 {
        if !locals[i].copyable && locals[i].type_name != "unknown" && !mir_local_moved_at_exit(locals[i].name, events) {
            statements.push(mir_statement::drop(mir_drop_stmt { slot: locals[i].id }))
        }
        i = i - 1
    }
}

func mir_local_moved_at_exit(string name, string[] events) bool {
    moved := false
    i := 0
    for i < len(events) {
        event := events[i]
        if starts_with(event, "move:") && slice(event, 5, len(event)) == name {
            moved = true
        } else if starts_with(event, "write:") && slice(event, 6, len(event)) == name {
            moved = false
        }
        i = i + 1
    }
    moved
}

func mir_extend_events(string[] base, string[] extra) string[] {
    i := 0
    for i < len(extra) {
        base = append(base, extra[i])
        i = i + 1
    }
    base
}

func mir_collect_locals(param[] params, block_expr block) mir_local_slot[] {
    locals := mir_local_slot[]()
    i := 0
    for i < len(params) {
        locals = append(locals, mir_local_slot { id: len(locals), name: params[i].name, kind: "param", version: 0, type_name: params[i].type_name, copyable: mir_type_is_copy(params[i].type_name) })
        i = i + 1
    }
    i = 0
    for i < len(block.statements) {
        switch block.statements[i] {
            stmt.let(let_stmt) : {
                if mir_find_local(locals, let_stmt.name) < 0 {
                    type_name := mir_expr_type_name(let_stmt.value)
                    if let_stmt.type_name.is_some() { type_name = let_stmt.type_name.unwrap() }
                    locals = append(locals, mir_local_slot { id: len(locals), name: let_stmt.name, kind: "local", version: 0, type_name: type_name, copyable: mir_type_is_copy(type_name) })
                }
            }
            _ : { }
        }
        i = i + 1
    }
    locals
}

func mir_expr_type_name(expr value) string {
    switch value {
        expr.int(_) : return "int"
        expr.string(_) : return "string"
        expr.bool(_) : return "bool"
        expr.call(call_value) : {
            switch call_value.callee.unwrap() {
                expr.name(name_value) : {
                    if name_value.name == "box" || name_value.name == "box_new" {
                        return "box[unknown]"
                    }
                }
                _ : { }
            }
            if call_value.inferred_type.is_some() { return call_value.inferred_type.unwrap() }
        }
        _ : { }
    }
    "unknown"
}

func mir_expr_events(expr value, mir_local_slot[] locals, bool consume) string[] {
    events := string[]()
    switch value {
        expr.name(name_expr) : {
            local_id := mir_find_local(locals, name_expr.name)
            if local_id >= 0 {
                if consume && !locals[local_id].copyable {
                    events = append(events, "move:" + name_expr.name)
                } else {
                    events = append(events, "read:" + name_expr.name)
                }
            } else {
                events = append(events, "read:" + name_expr.name)
            }
        }
        expr.borrow(borrow_expr) : {
            target_events := mir_expr_events(borrow_expr.target.unwrap(), locals, false)
            events = mir_extend_events(events, target_events)
            target_name := mir_place_name(borrow_expr.target.unwrap())
            if target_name != "" {
                if borrow_expr.mutable { events = append(events, "mutable:" + target_name) }
                else { events = append(events, "shared:" + target_name) }
            }
        }
        expr.binary(binary_expr) : {
            events = mir_extend_events(events, mir_expr_events(binary_expr.left.unwrap(), locals, false))
            events = mir_extend_events(events, mir_expr_events(binary_expr.right.unwrap(), locals, false))
        }
        expr.call(call_expr) : {
            events = mir_extend_events(events, mir_expr_events(call_expr.callee.unwrap(), locals, false))
            i := 0
            for i < len(call_expr.args) {
                events = mir_extend_events(events, mir_expr_events(call_expr.args[i], locals, true))
                i = i + 1
            }
        }
        expr.member(member_expr) : {
            events = mir_extend_events(events, mir_expr_events(member_expr.target.unwrap(), locals, consume))
        }
        expr.index(index_expr) : {
            events = mir_extend_events(events, mir_expr_events(index_expr.target.unwrap(), locals, false))
            events = mir_extend_events(events, mir_expr_events(index_expr.index.unwrap(), locals, false))
        }
        expr.block(block_expr) : {
            i := 0
            for i < len(block_expr.statements) {
                events = mir_extend_events(events, mir_stmt_events(block_expr.statements[i], locals))
                i = i + 1
            }
            if block_expr.final_expr.is_some() { events = mir_extend_events(events, mir_expr_events(block_expr.final_expr.unwrap(), locals, consume)) }
        }
        _ : { }
    }
    events
}

func mir_place_name(expr value) string {
    switch value {
        expr.name(name_expr) : return name_expr.name
        expr.member(member_expr) : return mir_place_name(member_expr.target.unwrap()) + "." + member_expr.member
        expr.index(index_expr) : return mir_place_name(index_expr.target.unwrap())
        _ : return ""
    }
}

func mir_stmt_events(stmt value, mir_local_slot[] locals) string[] {
    events := string[]()
    switch value {
        stmt.let(let_stmt) : {
            events = mir_extend_events(events, mir_expr_events(let_stmt.value, locals, true))
        }
        stmt.assign(assign_stmt) : {
            events = mir_extend_events(events, mir_expr_events(assign_stmt.value, locals, true))
            events = append(events, "write:" + assign_stmt.name)
        }
        stmt.increment(increment_stmt) : {
            events = append(events, "read:" + increment_stmt.name)
            events = append(events, "write:" + increment_stmt.name)
        }
        stmt.expr(expr_stmt) : {
            events = mir_extend_events(events, mir_expr_events(expr_stmt.expr, locals, false))
        }
        stmt.return(return_stmt) : {
            if return_stmt.value.is_some() { events = mir_extend_events(events, mir_expr_events(return_stmt.value.unwrap(), locals, true)) }
        }
        stmt.defer(defer_stmt) : { events = mir_extend_events(events, mir_expr_events(defer_stmt.expr, locals, true)) }
        stmt.sroutine(sroutine_stmt) : { events = mir_extend_events(events, mir_expr_events(sroutine_stmt.expr, locals, true)) }
        _ : { }
    }
    events
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
