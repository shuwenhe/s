package compile.internal.backend_elf64

use compile.internal.ir.lower.lower_main_to_mir
use compile.internal.mir.mir_graph
use compile.internal.mir.mir_basic_block
use compile.internal.mir.mir_statement
use compile.internal.mir.mir_control_edge
use compile.internal.mir.dump_graph
use compile.internal.ssa_core.build_pipeline as build_ssa_pipeline
use compile.internal.ssa_core.dump_pipeline as dump_ssa_pipeline
use compile.internal.ssa_core.dump_debug_map as dump_ssa_debug_map
use internal.buildcfg.goarch as buildcfg_goarch
use compile.internal.semantic.check_text
use compile.internal.syntax.parse_source
use s.assign_stmt
use s.binary_expr
use s.block_expr
use s.bool_expr
use s.c_for_stmt
use s.call_expr
use s.expr
use s.expr_stmt
use s.function_decl
use s.if_expr
use s.increment_stmt
use s.int_expr
use s.item
use s.name_expr
use s.source_file
use s.stmt
use s.string_expr
use s.var_stmt
use s.while_expr
use std.fs.make_temp_dir
use std.fs.read_to_string
use std.fs.write_text_file
use std.io.eprintln
use std.option.option
use std.process.run_process
use std.prelude.char_at
use std.prelude.len
use std.prelude.slice
use std.prelude.to_string
use std.vec.vec

struct backend_error {
    string message,
}

func ok_function(function_decl value) result[function_decl, backend_error] {
    result.ok(value);
}

func fail_function(string message) result[function_decl, backend_error] {
    result.err(backend_error {
        message: message,
    });
}

func ok_write_ops(vec[write_op] value) result[vec[write_op], backend_error] {
    result.ok(value);
}

func fail_write_ops(string message) result[vec[write_op], backend_error] {
    result.err(backend_error {
        message: message,
    });
}

func ok_value(value value) result[value, backend_error] {
    result.ok(value);
}

func fail_value(string message) result[value, backend_error] {
    result.err(backend_error {
        message: message,
    });
}

func ok_unit() result[(), backend_error] {
    result.ok(());
}

func fail_unit(string message) result[(), backend_error] {
    result.err(backend_error {
        message: message,
    });
}

func ok_int(int32 value) result[int32, backend_error] {
    result.ok(value);
}

func fail_int(string message) result[int32, backend_error] {
    result.err(backend_error {
        message: message,
    });
}

struct unit_value {}

enum value {
    int(int32),
    string(string),
    bool(bool),
    unit(unit_value),
}

struct binding {
    string name,
    value value,
}

struct write_op {
    int32 fd,
    string text,
}

struct mir_execution_result {
    vec[write_op] writes,
    int32 exit_code,
}

func build(string path, string output) int32 {
    var source_result = read_to_string(path)
    if source_result.is_err() {
        return report_failure("failed to read source file: " + path + ": " + source_result.unwrap_err().message)
    }

    var source = source_result.unwrap()
    var parsed_result = parse_source(source)
    if parsed_result.is_err() {
        return report_failure("parse failed: " + parsed_result.unwrap_err().message)
    }

    if check_text(source) != 0 {
        return report_failure("semantic check failed")
    }

    var mir_result = lower_main_to_mir(parsed_result.unwrap())
    if mir_result.is_err() {
        return report_failure("mir lowering failed: " + mir_result.unwrap_err())
    }
    var graph = mir_result.unwrap()
    var arch = buildcfg_goarch()

    var ssa_program = build_ssa_pipeline(dump_graph(graph), arch)
    var ssa_text = dump_ssa_pipeline(ssa_program)
    if ssa_text == "" {
        return report_failure("ssa lowering failed: empty pipeline")
    }
    var debug_map = dump_ssa_debug_map(ssa_program)
    if debug_map == "" {
        return report_failure("ssa debug map failed: empty map")
    }

    var abi_check = validate_abi_coverage(arch)
    if abi_check.is_err() {
        return report_failure(abi_check.unwrap_err().message)
    }

    var writes_result = compile_writes(graph)
    if writes_result.is_err() {
        return report_failure(writes_result.unwrap_err().message)
    }

    var exit_code_result = compile_exit_code(graph)
    if exit_code_result.is_err() {
        return report_failure(exit_code_result.unwrap_err().message)
    }

    var asm_text = emit_asm(writes_result.unwrap(), exit_code_result.unwrap())
    var temp_dir_result = make_temp_dir("s-build-")
    if temp_dir_result.is_err() {
        return report_failure("could not create temporary output directory: " + temp_dir_result.unwrap_err().message)
    }

    var temp_dir = temp_dir_result.unwrap()
    var asm_path = temp_dir + "/out.s"
    var obj_path = temp_dir + "/out.o"

    var write_result = write_text_file(asm_path, asm_text)
    if write_result.is_err() {
        return report_failure("failed to write assembly: " + write_result.unwrap_err().message)
    }

    var as_argv = vec[string]()
    as_argv.push("as");
    as_argv.push("-o");
    as_argv.push(obj_path);
    as_argv.push(asm_path);
    var as_result = run_process(as_argv)
    if as_result.is_err() {
        return report_failure("toolchain failed: " + as_result.unwrap_err().message)
    }

    var ld_argv = vec[string]()
    ld_argv.push("ld");
    ld_argv.push("-o");
    ld_argv.push(output);
    ld_argv.push(obj_path);
    var ld_result = run_process(ld_argv)
    if ld_result.is_err() {
        return report_failure("toolchain failed: " + ld_result.unwrap_err().message)
    }

    0
}

func compile_writes(mir_graph graph) result[vec[write_op], backend_error] {
    if graph.blocks.len() == 0 {
        return fail_write_ops("backend error: mir graph has no blocks")
    }

    var exec_result = execute_mir_graph(graph)
    if exec_result.is_err() {
        return fail_write_ops(exec_result.unwrap_err().message)
    }

    result::ok(exec_result.unwrap().writes)
}

func compile_exit_code(mir_graph graph) result[int32, backend_error] {
    if graph.blocks.len() == 0 {
        return fail_int("backend error: mir graph has no blocks")
    }

    var exec_result = execute_mir_graph(graph)
    if exec_result.is_err() {
        return fail_int(exec_result.unwrap_err().message)
    }

    result::ok(exec_result.unwrap().exit_code)
}

func execute_mir_graph(mir_graph graph) result[mir_execution_result, backend_error] {
    var writes = vec[write_op]()
    var current = graph.entry
    var steps = 0
    var max_steps = 100000

    while steps < max_steps {
        var block_result = find_mir_block(graph, current)
        if block_result.is_err() {
            return result::err(block_result.unwrap_err())
        }
        var block = block_result.unwrap()

        var si = 0
        while si < block.statements.len() {
            var stmt_result = execute_mir_statement(block.statements[si], writes)
            if stmt_result.is_err() {
                return result::err(stmt_result.unwrap_err())
            }
            si = si + 1
        }

        if block.terminator.kind == "return" {
            return result::ok(mir_execution_result {
                writes: writes,
                exit_code: 0,
            })
        }

        if block.terminator.kind == "jump" {
            if block.terminator.edges.len() == 0 {
                return result::err(backend_error { message: "backend error: jump terminator has no target" })
            }
            current = block.terminator.edges[0].target
            steps = steps + 1
            continue
        }

        if block.terminator.kind == "branch" {
            var target = select_branch_target(block.terminator.edges)
            if target < 0 {
                return result::err(backend_error { message: "backend error: branch terminator has no target" })
            }
            current = target
            steps = steps + 1
            continue
        }

        return result::err(backend_error { message: "backend error: unsupported mir terminator kind " + block.terminator.kind })
    }

    result::err(backend_error { message: "backend error: mir execution exceeded step limit" })
}

func find_mir_block(mir_graph graph, int32 id) result[mir_basic_block, backend_error] {
    var i = 0
    while i < graph.blocks.len() {
        if graph.blocks[i].id == id {
            return result::ok(graph.blocks[i])
        }
        i = i + 1
    }

    result::err(backend_error { message: "backend error: missing mir block id " + to_string(id) })
}

func execute_mir_statement(mir_statement statement, vec[write_op] mut writes) result[(), backend_error] {
    switch statement {
        mir_statement.eval(eval_stmt) : {
            if eval_stmt.args.len() > 0 {
                emit_print_from_line(eval_stmt.args[0], writes)
            }
            result::ok(())
        }
        _ : result::ok(()),
    }
}

func emit_print_from_line(string line, vec[write_op] mut writes) () {
    if has_substring(line, "eprintln(") {
        emit_call_line_to_write(line, "eprintln(", 2, writes)
        return
    }
    if has_substring(line, "println(") {
        emit_call_line_to_write(line, "println(", 1, writes)
        return
    }
}

func emit_call_line_to_write(string line, string callee, int32 fd, vec[write_op] mut writes) () {
    var arg_opt = extract_call_arg(line, callee)
    if arg_opt.is_none() {
        return
    }

    var rendered = render_literal_text(arg_opt.unwrap())
    writes.push(write_op {
        fd: fd,
        text: rendered + "\n",
    })
}

func render_literal_text(string raw_arg) string {
    var arg = trim_spaces(raw_arg)
    if is_quoted_literal(arg) {
        return decode_string_literal(arg)
    }
    if arg == "true" || arg == "false" {
        return arg
    }
    return to_string(parse_int_literal(arg))
}

func extract_call_arg(string line, string callee) option[string] {
    var call_index = index_of(line, callee)
    if call_index < 0 {
        return option.none
    }

    var start = call_index + len(callee)
    var end = index_of_from(line, ")", start)
    if end < 0 || end < start {
        return option.none
    }

    option.some(slice(line, start, end))
}

func is_quoted_literal(string text) bool {
    if len(text) < 2 {
        return false
    }
    char_at(text, 0) == "\"" && char_at(text, len(text) - 1) == "\""
}

func trim_spaces(string text) string {
    var start = 0
    var end = len(text)

    while start < end && is_space(char_at(text, start)) {
        start = start + 1
    }
    while end > start && is_space(char_at(text, end - 1)) {
        end = end - 1
    }

    slice(text, start, end)
}

func is_space(string ch) bool {
    ch == " " || ch == "\t" || ch == "\n" || ch == "\r"
}

func has_substring(string text, string needle) bool {
    index_of(text, needle) >= 0
}

func index_of(string text, string needle) int32 {
    index_of_from(text, needle, 0)
}

func index_of_from(string text, string needle, int32 start) int32 {
    if len(needle) == 0 {
        return start
    }
    if len(text) < len(needle) || start >= len(text) {
        return -1
    }

    var i = start
    var limit = len(text) - len(needle)
    while i <= limit {
        if slice(text, i, i + len(needle)) == needle {
            return i
        }
        i = i + 1
    }
    -1
}

func select_branch_target(vec[mir_control_edge] edges) int32 {
    if edges.len() == 0 {
        return -1
    }

    // Prefer explicit exits to avoid infinite loops in MVP walker.
    var i = 0
    while i < edges.len() {
        if edges[i].label == "false" || edges[i].label == "exit" || edges[i].label == "default" {
            return edges[i].target
        }
        i = i + 1
    }

    edges[0].target
}

func find_main(source_file source) result[function_decl, backend_error] {
    var i = 0
    while i < source.items.len() {
        switch source.items[i] {
            item.function(value) : {
                if value.body.is_some() && (value.sig.name == "main" || value.sig.name == "main") {
                    ok_function(value)
                }
            }
            _ : (),
        }
        i = i + 1
    }
    fail_function("backend error: entry function main not found")
}

func call_function(source_file source, string name, vec[value] args, vec[write_op] mut writes) result[value, backend_error] {
    var fn_result = find_function(source, name)
    if fn_result.is_err() {
        return fail_value(fn_result.unwrap_err().message)
    }

    var function = fn_result.unwrap()
    if function.body.is_none() {
        return fail_value("backend error: function " + name + " has no body")
    }
    if function.sig.params.len() != args.len() {
        return fail_value(
            "backend error: function "
                + name
                + " expects "
                + to_string(function.sig.params.len())
                + " args, got "
                + to_string(args.len())
        )
    }

    var env = vec[binding]()
    var pi = 0
    while pi < function.sig.params.len() {
        env.push(binding {
            name: function.sig.params[pi].name,
            value: args[pi],
        })
        pi = pi + 1
    }

    var body_result = execute_block_in_place(function.body.unwrap(), source, env, writes)
    if body_result.is_err() {
        return fail_value(body_result.unwrap_err().message)
    }
    ok_value(body_result.unwrap())
}

func find_function(source_file source, string name) result[function_decl, backend_error] {
    var i = 0
    while i < source.items.len() {
        switch source.items[i] {
            item.function(value) : {
                if value.sig.name == name {
                    result::ok(value)
                }
            }
            _ : (),
        }
        i = i + 1
    }
    result::err(backend_error { message: "backend error: unknown function " + name })
}

func execute_block(block_expr block, source_file source, vec[binding] mut env, vec[write_op] mut writes) result[value, backend_error] {
    var local_env = copy_bindings(env)
    var result = execute_block_in_place(block, source, local_env, writes)
    if result.is_err() {
        result::err(result.unwrap_err())
    }
    result::ok(result.unwrap())
}

func execute_block_in_place(block_expr block, source_file source, vec[binding] mut env, vec[write_op] mut writes) result[value, backend_error] {
    var si = 0
    while si < block.statements.len() {
        var stmt_result = execute_stmt(block.statements[si], source, env, writes)
        if stmt_result.is_err() {
            result::err(stmt_result.unwrap_err())
        }
        si = si + 1
    }

    switch block.final_expr {
        option.some(expr) : eval_expr(expr, source, env, writes),
        option.none : result::ok(value::unit(unit_value {})),
    }
}

func execute_stmt(stmt stmt, source_file source, vec[binding] mut env, vec[write_op] mut writes) result[(), backend_error] {
    switch stmt {
        stmt.var(value) : {
            var expr_result = eval_expr(value.value, source, env, writes)
            if expr_result.is_err() {
                result::err(expr_result.unwrap_err())
            }
            env.push(binding {
                name: value.name,
                value: expr_result.unwrap(),
            })
            result::ok(())
        }
        stmt.assign(value) : {
            var expr_result = eval_expr(value.value, source, env, writes)
            if expr_result.is_err() {
                result::err(expr_result.unwrap_err())
            }
            var index = find_binding_index(env, value.name)
            if index < 0 {
                result::err(backend_error { message: "backend error: unknown name " + value.name })
            }
            env.set(index, binding {
                name: value.name,
                value: expr_result.unwrap(),
            })
            result::ok(())
        }
        stmt.increment(value) : {
            var index = find_binding_index(env, value.name)
            if index < 0 {
                result::err(backend_error { message: "backend error: unknown name " + value.name })
            }
            var current = env.get(index).unwrap().value
            switch current {
                value.int(number) : {
                    env.set(index, binding {
                        name: value.name,
                        value: value.int(number + 1),
                    })
                    result::ok(())
                }
                _ : result::err(backend_error { message: "backend error: increment expects int32 for " + value.name }),
            }
        }
        stmt.c_for(value) : execute_c_for(value, source, env, writes),
        stmt.return(_) : result::err(backend_error { message: "backend error: return statements are not supported in the mvp backend" }),
        stmt.expr(value) : {
            var expr_result = eval_expr(value.expr, source, env, writes)
            if expr_result.is_err() {
                result::err(expr_result.unwrap_err())
            }
            result::ok(())
        }
        stmt.defer(_) : result::err(backend_error { message: "backend error: defer statements are not supported in the mvp backend" }),
    }
}

func execute_c_for(c_for_stmt value, source_file source, vec[binding] mut env, vec[write_op] mut writes) result[(), backend_error] {
    var loop_env = copy_bindings(env)

    var init_result = execute_stmt(value.init.value, source, loop_env, writes)
    if init_result.is_err() {
        result::err(init_result.unwrap_err())
    }

    while true {
        var cond_result = eval_expr(value.condition, source, loop_env, writes)
        if cond_result.is_err() {
            result::err(cond_result.unwrap_err())
        }
        var cond_value = cond_result.unwrap()
        switch cond_value {
            value.bool(flag) : {
                if !flag {
                    break
                }
            }
            _ : result::err(backend_error { message: "backend error: for condition must be bool" }),
        }

        var body_result = execute_block_in_place(value.body, source, loop_env, writes)
        if body_result.is_err() {
            result::err(body_result.unwrap_err())
        }

        var step_result = execute_stmt(value.step.value, source, loop_env, writes)
        if step_result.is_err() {
            result::err(step_result.unwrap_err())
        }
    }

    propagate_bindings(env, loop_env)
    result::ok(())
}

func eval_expr(expr expr, source_file source, vec[binding] mut env, vec[write_op] mut writes) result[value, backend_error] {
    switch expr {
        expr.int(value) : result::ok(value.int(parse_int_literal(value.value))),
        expr.string(value) : result::ok(value.string(decode_string_literal(value.value))),
        expr.bool(value) : result::ok(value.bool(value.value)),
        expr.name(value) : lookup_value(env, value.name),
        expr.binary(value) : eval_binary(value, source, env, writes),
        expr.call(value) : eval_call(value, source, env, writes),
        expr.if(value) : eval_if_expr(value, source, env, writes),
        expr.while(value) : eval_while_expr(value, source, env, writes),
        expr.block(value) : execute_block(value, source, env, writes),
        expr.for(_) : result::err(backend_error { message: "backend error: for expressions are not supported in the mvp backend" }),
        expr.switch(_) : result::err(backend_error { message: "backend error: switch expressions are not supported in the mvp backend" }),
        expr.borrow(_) : result::err(backend_error { message: "backend error: borrow expressions are not supported in the mvp backend" }),
        expr.member(_) : result::err(backend_error { message: "backend error: member expressions are not supported in the mvp backend" }),
        expr.index(_) : result::err(backend_error { message: "backend error: index expressions are not supported in the mvp backend" }),
        expr.array(_) : result::err(backend_error { message: "backend error: array literals are not supported in the mvp backend" }),
        expr.map(_) : result::err(backend_error { message: "backend error: map literals are not supported in the mvp backend" }),
    }
}

func eval_binary(binary_expr value, source_file source, vec[binding] mut env, vec[write_op] mut writes) result[value, backend_error] {
    var left_result = eval_expr(value.left.value, source, env, writes)
    if left_result.is_err() {
        result::err(left_result.unwrap_err())
    }
    var right_result = eval_expr(value.right.value, source, env, writes)
    if right_result.is_err() {
        result::err(right_result.unwrap_err())
    }

    var left = left_result.unwrap()
    var right = right_result.unwrap()

    switch value.op {
        "+" : add_values(left, right),
        "-" : numeric_binary(left, right, value.op),
        "*" : numeric_binary(left, right, value.op),
        "/" : numeric_binary(left, right, value.op),
        "==" : compare_values(left, right, true),
        "!=" : compare_values(left, right, false),
        "<" : ordered_compare(left, right, value.op),
        "<=" : ordered_compare(left, right, value.op),
        ">" : ordered_compare(left, right, value.op),
        ">=" : ordered_compare(left, right, value.op),
        "&&" : logical_binary(left, right, true),
        "||" : logical_binary(left, right, false),
        _ : result::err(backend_error { message: "backend error: unsupported binary operator " + value.op }),
    }
}

func eval_call(call_expr value, source_file source, vec[binding] mut env, vec[write_op] mut writes) result[value, backend_error] {
    switch value.callee.value {
        expr.name(callee_name) : {
            if callee_name.name == "println" || callee_name.name == "eprintln" {
                return eval_print_call(callee_name.name, value.args, source, env, writes)
            }

            var arg_values = vec[value]()
            var ai = 0
            while ai < value.args.len() {
                var arg_result = eval_expr(value.args[ai], source, env, writes)
                if arg_result.is_err() {
                    result::err(arg_result.unwrap_err())
                }
                arg_values.push(arg_result.unwrap())
                ai = ai + 1
            }
            call_function(source, callee_name.name, arg_values, writes)
        }
        _ : result::err(backend_error { message: "backend error: unsupported call target" }),
    }
}

func eval_print_call(string name, vec[expr] args, source_file source, vec[binding] mut env, vec[write_op] mut writes) result[value, backend_error] {
    if args.len() > 1 {
        result::err(backend_error { message: "backend error: " + name + " expects at most one argument" })
    }

    var text = ""
    if args.len() == 1 {
        var arg_result = eval_expr(args[0], source, env, writes)
        if arg_result.is_err() {
            result::err(arg_result.unwrap_err())
        }
        text = stringify_value(arg_result.unwrap())
    }

    var op_text = text + "\n"
    if name == "println" {
        writes.push(write_op { fd: 1, text: op_text });
    } else {
        writes.push(write_op { fd: 2, text: op_text });
    }
    result::ok(value.unit(unit_value {}))
}

func eval_if_expr(if_expr value, source_file source, vec[binding] mut env, vec[write_op] mut writes) result[value, backend_error] {
    var cond_result = eval_expr(value.condition.value, source, env, writes)
    if cond_result.is_err() {
        result::err(cond_result.unwrap_err())
    }

    switch cond_result.unwrap() {
        value.bool(flag) : {
            if flag {
                execute_block_in_place(value.then_branch, source, env, writes)
            } else {
                switch value.else_branch {
                    option.some(expr) : eval_expr(expr.value, source, env, writes),
                    option.none : result::ok(value.unit(unit_value {})),
                }
            }
        }
        _ : result::err(backend_error { message: "backend error: if condition must be bool" }),
    }
}

func eval_while_expr(while_expr value, source_file source, vec[binding] mut env, vec[write_op] mut writes) result[value, backend_error] {
    while true {
        var cond_result = eval_expr(value.condition.value, source, env, writes)
        if cond_result.is_err() {
            result::err(cond_result.unwrap_err())
        }
        switch cond_result.unwrap() {
            value.bool(flag) : {
                if !flag {
                    break
                }
            }
            _ : result::err(backend_error { message: "backend error: while condition must be bool" }),
        }

        var body_result = execute_block_in_place(value.body, source, env, writes)
        if body_result.is_err() {
            result::err(body_result.unwrap_err())
        }
    }
    result::ok(value.unit(unit_value {}))
}

func lookup_value(vec[binding] env, string name) result[value, backend_error] {
    var index = find_binding_index(env, name)
    if index < 0 {
        result::err(backend_error { message: "backend error: unknown name " + name })
    }
    result::ok(env[index].value)
}

func add_values(value left, value right) result[value, backend_error] {
    switch left {
        value.int(left_int) : {
            switch right {
                value.int(right_int) : result::ok(value.int(left_int + right_int)),
                _ : result::err(backend_error { message: "backend error: + expects matching types" }),
            }
        }
        value.string(left_text) : {
            switch right {
                value.string(right_text) : result::ok(value.string(left_text + right_text)),
                _ : result::err(backend_error { message: "backend error: + expects matching string types" }),
            }
        }
        _ : result::err(backend_error { message: "backend error: unsupported + operands" }),
    }
}

func numeric_binary(value left, value right, string op) result[value, backend_error] {
    switch left {
        value.int(left_int) : {
            switch right {
                value.int(right_int) : {
                    if op == "-" {
                        result::ok(value.int(left_int - right_int))
                    } else if op == "*" {
                        result::ok(value.int(left_int * right_int))
                    } else if op == "/" {
                        if right_int == 0 {
                            result::err(backend_error { message: "backend error: division by zero" })
                        } else {
                            result::ok(value.int(left_int / right_int))
                        }
                    } else {
                        result::err(backend_error { message: "backend error: unsupported numeric operator " + op })
                    }
                }
                _ : result::err(backend_error { message: "backend error: numeric operator expects int32 operands" }),
            }
        }
        _ : result::err(backend_error { message: "backend error: numeric operator expects int32 operands" }),
    }
}

func compare_values(value left, value right, bool equal) result[value, backend_error] {
    var same = false
    switch left {
        value.int(left_int) : {
            switch right {
                value.int(right_int) : same = left_int == right_int,
                _ : result::err(backend_error { message: "backend error: comparison expects matching types" }),
            }
        }
        value.string(left_text) : {
            switch right {
                value.string(right_text) : same = left_text == right_text,
                _ : result::err(backend_error { message: "backend error: comparison expects matching types" }),
            }
        }
        value.bool(left_bool) : {
            switch right {
                value.bool(right_bool) : same = left_bool == right_bool,
                _ : result::err(backend_error { message: "backend error: comparison expects matching types" }),
            }
        }
        value.unit(_) : {
            switch right {
                value.unit(_) : same = true,
                _ : result::err(backend_error { message: "backend error: comparison expects matching types" }),
            }
        }
    }

    if equal {
        result::ok(value.bool(same))
    } else {
        result::ok(value.bool(!same))
    }
}

func ordered_compare(value left, value right, string op) result[value, backend_error] {
    switch left {
        value.int(left_int) : {
            switch right {
                value.int(right_int) : {
                    if op == "<" {
                        result::ok(value.bool(left_int < right_int))
                    } else if op == "<=" {
                        result::ok(value.bool(left_int <= right_int))
                    } else if op == ">" {
                        result::ok(value.bool(left_int > right_int))
                    } else if op == ">=" {
                        result::ok(value.bool(left_int >= right_int))
                    } else {
                        result::err(backend_error { message: "backend error: unsupported ordered comparison " + op })
                    }
                }
                _ : result::err(backend_error { message: "backend error: ordered comparison expects int32 operands" }),
            }
        }
        _ : result::err(backend_error { message: "backend error: ordered comparison expects int32 operands" }),
    }
}

func logical_binary(value left, value right, bool and_op) result[value, backend_error] {
    switch left {
        value.bool(left_bool) : {
            switch right {
                value.bool(right_bool) : {
                    if and_op {
                        result::ok(value.bool(left_bool && right_bool))
                    } else {
                        result::ok(value.bool(left_bool || right_bool))
                    }
                }
                _ : result::err(backend_error { message: "backend error: logical operator expects bool operands" }),
            }
        }
        _ : result::err(backend_error { message: "backend error: logical operator expects bool operands" }),
    }
}

func value_to_exit_code(value value) result[int32, backend_error] {
    switch value {
        value.int(number) : result::ok(number),
        value.bool(flag) : result::ok(if flag { 1 } else { 0 }),
        value.unit(_) : result::ok(0),
        value.string(_) : result::err(backend_error { message: "backend error: main cannot return string" }),
    }
}

func stringify_value(value value) string {
    switch value {
        value.int(number) : to_string(number),
        value.string(text) : text,
        value.bool(flag) : if flag { "true" } else { "false" },
        value.unit(_) : "()",
    }
}

func parse_int_literal(string literal) int32 {
    var value = literal
    var sign = 1
    var index = 0
    if len(value) > 0 && char_at(value, 0) == "-" {
        sign = -1
        index = 1
    }

    var out = 0
    while index < len(value) {
        var ch = char_at(value, index)
        if ch != "_" {
            var digit = digit_value(ch)
            if digit < 0 {
                return 0
            }
            out = out * 10 + digit
        }
        index = index + 1
    }
    sign * out
}

func digit_value(string ch) int32 {
    if ch == "0" {
        return 0
    }
    if ch == "1" {
        return 1
    }
    if ch == "2" {
        return 2
    }
    if ch == "3" {
        return 3
    }
    if ch == "4" {
        return 4
    }
    if ch == "5" {
        return 5
    }
    if ch == "6" {
        return 6
    }
    if ch == "7" {
        return 7
    }
    if ch == "8" {
        return 8
    }
    if ch == "9" {
        return 9
    }
    -1
}

func decode_string_literal(string literal) string {
    var text = literal
    if len(text) < 2 {
        return text
    }

    var out = ""
    var index = 1
    while index < len(text) - 1 {
        var ch = char_at(text, index)
        if ch != "\\" {
            out = out + ch
            index = index + 1
            continue
        }

        if index + 1 >= len(text) - 1 {
            out = out + "\\"
            break
        }

        var esc = char_at(text, index + 1)
        if esc == "n" {
            out = out + "\n"
        } else if esc == "t" {
            out = out + "\t"
        } else if esc == "r" {
            out = out + "\r"
        } else if esc == "\"" {
            out = out + "\""
        } else if esc == "\\" {
            out = out + "\\"
        } else {
            out = out + esc
        }
        index = index + 2
    }
    out
}

func emit_asm(vec[write_op] writes, int32 exit_code) string {
    var arch = buildcfg_goarch()
    if arch == "arm64" {
        return emit_asm_arm64(writes, exit_code)
    }
    return emit_asm_amd64(writes, exit_code)
}

func validate_abi_coverage(string arch) result[(), backend_error] {
    var i = 0
    while i < 8 {
        if abi_int_arg_reg(arch, i) == "" {
            return result::err(backend_error { message: "backend error: missing integer argument ABI mapping for arg " + to_string(i) + " on " + arch })
        }
        if abi_float_arg_reg(arch, i) == "" {
            return result::err(backend_error { message: "backend error: missing float argument ABI mapping for arg " + to_string(i) + " on " + arch })
        }
        i = i + 1
    }

    if abi_int_ret_reg(arch) == "" {
        return result::err(backend_error { message: "backend error: missing integer return ABI mapping on " + arch })
    }
    if abi_float_ret_reg(arch) == "" {
        return result::err(backend_error { message: "backend error: missing float return ABI mapping on " + arch })
    }
    if abi_callee_saved_count(arch) == 0 {
        return result::err(backend_error { message: "backend error: missing callee-saved ABI set on " + arch })
    }
    result::ok(())
}

func abi_int_arg_reg(string arch, int32 index) string {
    if arch == "arm64" {
        if index == 0 { return "x0" }
        if index == 1 { return "x1" }
        if index == 2 { return "x2" }
        if index == 3 { return "x3" }
        if index == 4 { return "x4" }
        if index == 5 { return "x5" }
        if index == 6 { return "x6" }
        if index == 7 { return "x7" }
        return ""
    }

    if index == 0 { return "%rdi" }
    if index == 1 { return "%rsi" }
    if index == 2 { return "%rdx" }
    if index == 3 { return "%rcx" }
    if index == 4 { return "%r8" }
    if index == 5 { return "%r9" }
    if index == 6 { return "stack+0" }
    if index == 7 { return "stack+8" }
    ""
}

func abi_float_arg_reg(string arch, int32 index) string {
    if arch == "arm64" {
        if index == 0 { return "v0" }
        if index == 1 { return "v1" }
        if index == 2 { return "v2" }
        if index == 3 { return "v3" }
        if index == 4 { return "v4" }
        if index == 5 { return "v5" }
        if index == 6 { return "v6" }
        if index == 7 { return "v7" }
        return ""
    }

    if index == 0 { return "%xmm0" }
    if index == 1 { return "%xmm1" }
    if index == 2 { return "%xmm2" }
    if index == 3 { return "%xmm3" }
    if index == 4 { return "%xmm4" }
    if index == 5 { return "%xmm5" }
    if index == 6 { return "%xmm6" }
    if index == 7 { return "%xmm7" }
    ""
}

func abi_int_ret_reg(string arch) string {
    if arch == "arm64" {
        return "x0"
    }
    "%rax"
}

func abi_float_ret_reg(string arch) string {
    if arch == "arm64" {
        return "v0"
    }
    "%xmm0"
}

func abi_callee_saved_count(string arch) int32 {
    if arch == "arm64" {
        return 12
    }
    6
}

func emit_asm_amd64(vec[write_op] writes, int32 exit_code) string {
    var data_lines = vec[string]()
    var text_lines = vec[string]()
    data_lines.push(".section .data")
    text_lines.push(".section .text")
    text_lines.push(".global _start")
    text_lines.push(".global s_main")
    text_lines.push("_start:")
    text_lines.push("    andq $-16, %rsp")
    text_lines.push("    call s_main")
    text_lines.push("    mov %eax, %edi")
    text_lines.push("    mov $60, %rax")
    text_lines.push("    syscall")
    text_lines.push("")
    text_lines.push("s_main:")
    text_lines.push("    push %rbp")
    text_lines.push("    mov %rsp, %rbp")
    text_lines.push("    sub $16, %rsp")

    var message_index = 0
    var i = 0
    while i < writes.len() {
        append_write_op(data_lines, text_lines, writes[i], message_index)
        message_index = message_index + 1
        i = i + 1
    }

    text_lines.push("    mov $" + to_string(exit_code) + ", %eax")
    text_lines.push("    leave")
    text_lines.push("    ret")

    join_lines(data_lines) + "\n\n" + join_lines(text_lines) + "\n"
}

func emit_asm_arm64(vec[write_op] writes, int32 exit_code) string {
    var data_lines = vec[string]()
    var text_lines = vec[string]()
    data_lines.push(".section .data")
    text_lines.push(".section .text")
    text_lines.push(".global _start")
    text_lines.push(".global s_main")
    text_lines.push("_start:")
    text_lines.push("    bl s_main")
    text_lines.push("    mov x8, #93")
    text_lines.push("    svc #0")
    text_lines.push("")
    text_lines.push("s_main:")
    text_lines.push("    stp x29, x30, [sp, #-16]!")
    text_lines.push("    mov x29, sp")

    var message_index = 0
    var i = 0
    while i < writes.len() {
        append_write_op_arm64(data_lines, text_lines, writes[i], message_index)
        message_index = message_index + 1
        i = i + 1
    }

    text_lines.push("    mov x0, #" + to_string(exit_code))
    text_lines.push("    ldp x29, x30, [sp], #16")
    text_lines.push("    ret")

    join_lines(data_lines) + "\n\n" + join_lines(text_lines) + "\n"
}

func append_write_op(vec[string] data_lines, vec[string] text_lines, write_op op, int32 index) () {
    var label = "message_" + to_string(index)
    data_lines.push(label + ":")
    data_lines.push("    .ascii \"" + escape_asm_string(op.text) + "\"")
    text_lines.push("    mov $1, %rax")
    text_lines.push("    mov $" + to_string(op.fd) + ", %rdi")
    text_lines.push("    lea " + label + "(%rip), %rsi")
    text_lines.push("    mov $" + to_string(len(op.text)) + ", %rdx")
    text_lines.push("    syscall")
}

func append_write_op_arm64(vec[string] data_lines, vec[string] text_lines, write_op op, int32 index) () {
    var label = "message_" + to_string(index)
    data_lines.push(label + ":")
    data_lines.push("    .ascii \"" + escape_asm_string(op.text) + "\"")

    text_lines.push("    mov x8, #64")
    text_lines.push("    mov x0, #" + to_string(op.fd))
    text_lines.push("    adrp x1, " + label)
    text_lines.push("    add x1, x1, :lo12:" + label)
    text_lines.push("    ldr x2, =" + to_string(len(op.text)))
    text_lines.push("    svc #0")
}

func escape_asm_string(string text) string {
    var out = ""
    var i = 0
    while i < len(text) {
        var ch = char_at(text, i)
        if ch == "\\" {
            out = out + "\\\\"
        } else if ch == "\"" {
            out = out + "\\\""
        } else if ch == "\n" {
            out = out + "\\n"
        } else if ch == "\t" {
            out = out + "\\t"
        } else if ch == "\r" {
            out = out + "\\r"
        } else {
            out = out + ch
        }
        i = i + 1
    }
    out
}

func copy_bindings(vec[binding] source) vec[binding] {
    var out = vec[binding]()
    var i = 0
    while i < source.len() {
        out.push(source[i])
        i = i + 1
    }
    out
}

func find_binding_index(vec[binding] env, string name) int32 {
    var i = env.len()
    while i > 0 {
        i = i - 1
        if env[i].name == name {
            return i
        }
    }
    -1
}

func propagate_bindings(vec[binding] mut outer, vec[binding] inner) () {
    var i = 0
    while i < inner.len() {
        var index = find_binding_index(outer, inner[i].name)
        if index >= 0 {
            outer.set(index, inner[i])
        }
        i = i + 1
    }
}

func join_lines(vec[string] lines) string {
    join_with(lines, "\n")
}

func join_with(vec[string] values, string sep) string {
    var out = ""
    var first = true
    var i = 0
    while i < values.len() {
        if !first {
            out = out + sep
        }
        out = out + values[i]
        first = false
        i = i + 1
    }
    out
}

func report_failure(string message) int32 {
    eprintln("backend error: " + message)
    1
}
