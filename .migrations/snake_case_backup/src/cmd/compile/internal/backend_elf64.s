package compile.internal.backend_elf64

use compile.internal.semantic.check_text
use compile.internal.syntax.parse_source
use s.assign_stmt
use s.binary_expr
use s.block_expr
use s.bool_expr
use s.c_for_stmt
use s.call_expr
use s.Expr
use s.expr_stmt
use s.function_decl
use s.if_expr
use s.increment_stmt
use s.int_expr
use s.Item
use s.name_expr
use s.source_file
use s.Stmt
use s.string_expr
use s.var_stmt
use s.while_expr
use std.fs.make_temp_dir
use std.fs.read_to_string
use std.fs.write_text_file
use std.io.eprintln
use std.option.Option
use std.process.run_process
use std.prelude.char_at
use std.prelude.len
use std.prelude.to_string
use std.vec.Vec

struct backend_error {
    string message,
}

func ok_function(function_decl value) Result[function_decl, backend_error] {
    Result.Ok(value);
}

func fail_function(string message) Result[function_decl, backend_error] {
    Result.Err(backend_error {
        message: message,
    });
}

func ok_write_ops(Vec[write_op] value) Result[Vec[write_op], backend_error] {
    Result.Ok(value);
}

func fail_write_ops(string message) Result[Vec[write_op], backend_error] {
    Result.Err(backend_error {
        message: message,
    });
}

func ok_value(Value value) Result[Value, backend_error] {
    Result.Ok(value);
}

func fail_value(string message) Result[Value, backend_error] {
    Result.Err(backend_error {
        message: message,
    });
}

func ok_unit() Result[(), backend_error] {
    Result.Ok(());
}

func fail_unit(string message) Result[(), backend_error] {
    Result.Err(backend_error {
        message: message,
    });
}

func ok_int(int32 value) Result[int32, backend_error] {
    Result.Ok(value);
}

func fail_int(string message) Result[int32, backend_error] {
    Result.Err(backend_error {
        message: message,
    });
}

struct unit_value {}

enum Value {
    Int(int32),
    String(string),
    Bool(bool),
    Unit(unit_value),
}

struct Binding {
    string name,
    Value value,
}

struct write_op {
    int32 fd,
    string text,
}

func Build(string path, string output) int32 {
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

    var writes_result = compile_writes(parsed_result.unwrap())
    if writes_result.is_err() {
        return report_failure(writes_result.unwrap_err().message)
    }

    var exit_code_result = compile_exit_code(parsed_result.unwrap())
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

    var as_argv = Vec[string]()
    as_argv.push("as");
    as_argv.push("-o");
    as_argv.push(obj_path);
    as_argv.push(asm_path);
    var as_result = run_process(as_argv)
    if as_result.is_err() {
        return report_failure("toolchain failed: " + as_result.unwrap_err().message)
    }

    var ld_argv = Vec[string]()
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

func compile_writes(source_file source) Result[Vec[write_op], backend_error] {
    switch find_main(source) {
        Result.Err(err) : Result.Err(err),
        Result.Ok(main_function) : {
            var writes = Vec[write_op]()
            var main_result_value = call_function(source, main_function.sig.name, Vec[Value](), writes)
            switch main_result_value {
                Result.Err(err) : Result.Err(err),
                Result.Ok(value) : {
                    Result.Ok(writes)
                }
            }
        }
    }
}

func compile_exit_code(source_file source) Result[int32, backend_error] {
    switch find_main(source) {
        Result.Err(err) : Result.Err(err),
        Result.Ok(main_function) : {
            var writes = Vec[write_op]()
            var main_result_value = call_function(source, main_function.sig.name, Vec[Value](), writes)
            switch main_result_value {
                Result.Err(err) : Result.Err(err),
                Result.Ok(value) : value_to_exit_code(value),
            }
        }
    }
}

func find_main(source_file source) Result[function_decl, backend_error] {
    var i = 0
    while i < source.items.len() {
        switch source.items[i] {
            Item.Function(value) : {
                if value.body.is_some() && (value.sig.name == "main" || value.sig.name == "Main") {
                    ok_function(value)
                }
            }
            _ : (),
        }
        i = i + 1
    }
    fail_function("backend error: entry function main not found")
}

func call_function(source_file source, string name, Vec[Value] args, Vec[write_op] mut writes) Result[Value, backend_error] {
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

    var env = Vec[Binding]()
    var pi = 0
    while pi < function.sig.params.len() {
        env.push(Binding {
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

func find_function(source_file source, string name) Result[function_decl, backend_error] {
    var i = 0
    while i < source.items.len() {
        switch source.items[i] {
            Item.Function(value) : {
                if value.sig.name == name {
                    Result::Ok(value)
                }
            }
            _ : (),
        }
        i = i + 1
    }
    Result::Err(backend_error { message: "backend error: unknown function " + name })
}

func execute_block(block_expr block, source_file source, Vec[Binding] mut env, Vec[write_op] mut writes) Result[Value, backend_error] {
    var local_env = copy_bindings(env)
    var result = execute_block_in_place(block, source, local_env, writes)
    if result.is_err() {
        Result::Err(result.unwrap_err())
    }
    Result::Ok(result.unwrap())
}

func execute_block_in_place(block_expr block, source_file source, Vec[Binding] mut env, Vec[write_op] mut writes) Result[Value, backend_error] {
    var si = 0
    while si < block.statements.len() {
        var stmt_result = execute_stmt(block.statements[si], source, env, writes)
        if stmt_result.is_err() {
            Result::Err(stmt_result.unwrap_err())
        }
        si = si + 1
    }

    switch block.final_expr {
        Option.Some(expr) : eval_expr(expr, source, env, ops),
        Option.None : Result::Ok(Value::Unit(unit_value {})),
    }
}

func execute_stmt(Stmt stmt, source_file source, Vec[Binding] mut env, Vec[write_op] mut writes) Result[(), backend_error] {
    switch stmt {
        Stmt.Var(value) : {
            var expr_result = eval_expr(value.value, source, env, writes)
            if expr_result.is_err() {
                Result::Err(expr_result.unwrap_err())
            }
            env.push(Binding {
                name: value.name,
                value: expr_result.unwrap(),
            })
            Result::Ok(())
        }
        Stmt.Assign(value) : {
            var expr_result = eval_expr(value.value, source, env, writes)
            if expr_result.is_err() {
                Result::Err(expr_result.unwrap_err())
            }
            var index = find_binding_index(env, value.name)
            if index < 0 {
                Result::Err(backend_error { message: "backend error: unknown name " + value.name })
            }
            env.set(index, Binding {
                name: value.name,
                value: expr_result.unwrap(),
            })
            Result::Ok(())
        }
        Stmt.Increment(value) : {
            var index = find_binding_index(env, value.name)
            if index < 0 {
                Result::Err(backend_error { message: "backend error: unknown name " + value.name })
            }
            var current = env.get(index).unwrap().value
            switch current {
                Value.Int(number) : {
                    env.set(index, Binding {
                        name: value.name,
                        value: Value.Int(number + 1),
                    })
                    Result::Ok(())
                }
                _ : Result::Err(backend_error { message: "backend error: increment expects int32 for " + value.name }),
            }
        }
        Stmt.c_for(value) : execute_c_for(value, source, env, writes),
        Stmt.Return(_) : Result::Err(backend_error { message: "backend error: return statements are not supported in the MVP backend" }),
        Stmt.Expr(value) : {
            var expr_result = eval_expr(value.expr, source, env, writes)
            if expr_result.is_err() {
                Result::Err(expr_result.unwrap_err())
            }
            Result::Ok(())
        }
        Stmt.Defer(_) : Result::Err(backend_error { message: "backend error: defer statements are not supported in the MVP backend" }),
    }
}

func execute_c_for(c_for_stmt value, source_file source, Vec[Binding] mut env, Vec[write_op] mut writes) Result[(), backend_error] {
    var loop_env = copy_bindings(env)

    var init_result = execute_stmt(value.init.value, source, loop_env, writes)
    if init_result.is_err() {
        Result::Err(init_result.unwrap_err())
    }

    while true {
        var cond_result = eval_expr(value.condition, source, loop_env, writes)
        if cond_result.is_err() {
            Result::Err(cond_result.unwrap_err())
        }
        var cond_value = cond_result.unwrap()
        switch cond_value {
            Value.Bool(flag) : {
                if !flag {
                    break
                }
            }
            _ : Result::Err(backend_error { message: "backend error: for condition must be bool" }),
        }

        var body_result = execute_block_in_place(value.body, source, loop_env, writes)
        if body_result.is_err() {
            Result::Err(body_result.unwrap_err())
        }

        var step_result = execute_stmt(value.step.value, source, loop_env, writes)
        if step_result.is_err() {
            Result::Err(step_result.unwrap_err())
        }
    }

    propagate_bindings(env, loop_env)
    Result::Ok(())
}

func eval_expr(Expr expr, source_file source, Vec[Binding] mut env, Vec[write_op] mut writes) Result[Value, backend_error] {
    switch expr {
        Expr.Int(value) : Result::Ok(Value.Int(parse_int_literal(value.value))),
        Expr.string(value) : Result::Ok(Value.String(decode_string_literal(value.value))),
        Expr.Bool(value) : Result::Ok(Value.Bool(value.value)),
        Expr.Name(value) : lookup_value(env, value.name),
        Expr.Binary(value) : eval_binary(value, source, env, writes),
        Expr.Call(value) : eval_call(value, source, env, writes),
        Expr.If(value) : eval_if_expr(value, source, env, writes),
        Expr.While(value) : eval_while_expr(value, source, env, writes),
        Expr.Block(value) : execute_block(value, source, env, writes),
        Expr.For(_) : Result::Err(backend_error { message: "backend error: for expressions are not supported in the MVP backend" }),
        Expr.Switch(_) : Result::Err(backend_error { message: "backend error: switch expressions are not supported in the MVP backend" }),
        Expr.Borrow(_) : Result::Err(backend_error { message: "backend error: borrow expressions are not supported in the MVP backend" }),
        Expr.Member(_) : Result::Err(backend_error { message: "backend error: member expressions are not supported in the MVP backend" }),
        Expr.Index(_) : Result::Err(backend_error { message: "backend error: index expressions are not supported in the MVP backend" }),
        Expr.Array(_) : Result::Err(backend_error { message: "backend error: array literals are not supported in the MVP backend" }),
        Expr.Map(_) : Result::Err(backend_error { message: "backend error: map literals are not supported in the MVP backend" }),
    }
}

func eval_binary(binary_expr value, source_file source, Vec[Binding] mut env, Vec[write_op] mut writes) Result[Value, backend_error] {
    var left_result = eval_expr(value.left.value, source, env, writes)
    if left_result.is_err() {
        Result::Err(left_result.unwrap_err())
    }
    var right_result = eval_expr(value.right.value, source, env, writes)
    if right_result.is_err() {
        Result::Err(right_result.unwrap_err())
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
        _ : Result::Err(backend_error { message: "backend error: unsupported binary operator " + value.op }),
    }
}

func eval_call(call_expr value, source_file source, Vec[Binding] mut env, Vec[write_op] mut writes) Result[Value, backend_error] {
    switch value.callee.value {
        Expr.Name(callee_name) : {
            if callee_name.name == "println" || callee_name.name == "eprintln" {
                return eval_print_call(callee_name.name, value.args, source, env, writes)
            }

            var arg_values = Vec[Value]()
            var ai = 0
            while ai < value.args.len() {
                var arg_result = eval_expr(value.args[ai], source, env, writes)
                if arg_result.is_err() {
                    Result::Err(arg_result.unwrap_err())
                }
                arg_values.push(arg_result.unwrap())
                ai = ai + 1
            }
            call_function(source, callee_name.name, arg_values, writes)
        }
        _ : Result::Err(backend_error { message: "backend error: unsupported call target" }),
    }
}

func eval_print_call(string name, Vec[Expr] args, source_file source, Vec[Binding] mut env, Vec[write_op] mut writes) Result[Value, backend_error] {
    if args.len() > 1 {
        Result::Err(backend_error { message: "backend error: " + name + " expects at most one argument" })
    }

    var text = ""
    if args.len() == 1 {
        var arg_result = eval_expr(args[0], source, env, writes)
        if arg_result.is_err() {
            Result::Err(arg_result.unwrap_err())
        }
        text = stringify_value(arg_result.unwrap())
    }

    var op_text = text + "\n"
    if name == "println" {
        writes.push(write_op { fd: 1, text: op_text });
    } else {
        writes.push(write_op { fd: 2, text: op_text });
    }
    Result::Ok(Value.Unit(unit_value {}))
}

func eval_if_expr(if_expr value, source_file source, Vec[Binding] mut env, Vec[write_op] mut writes) Result[Value, backend_error] {
    var cond_result = eval_expr(value.condition.value, source, env, writes)
    if cond_result.is_err() {
        Result::Err(cond_result.unwrap_err())
    }

    switch cond_result.unwrap() {
        Value.Bool(flag) : {
            if flag {
                execute_block_in_place(value.then_branch, source, env, writes)
            } else {
                switch value.else_branch {
                    Option.Some(expr) : eval_expr(expr.value, source, env, writes),
                    Option.None : Result::Ok(Value.Unit(unit_value {})),
                }
            }
        }
        _ : Result::Err(backend_error { message: "backend error: if condition must be bool" }),
    }
}

func eval_while_expr(while_expr value, source_file source, Vec[Binding] mut env, Vec[write_op] mut writes) Result[Value, backend_error] {
    while true {
        var cond_result = eval_expr(value.condition.value, source, env, writes)
        if cond_result.is_err() {
            Result::Err(cond_result.unwrap_err())
        }
        switch cond_result.unwrap() {
            Value.Bool(flag) : {
                if !flag {
                    break
                }
            }
            _ : Result::Err(backend_error { message: "backend error: while condition must be bool" }),
        }

        var body_result = execute_block_in_place(value.body, source, env, writes)
        if body_result.is_err() {
            Result::Err(body_result.unwrap_err())
        }
    }
    Result::Ok(Value.Unit(unit_value {}))
}

func lookup_value(Vec[Binding] env, string name) Result[Value, backend_error] {
    var index = find_binding_index(env, name)
    if index < 0 {
        Result::Err(backend_error { message: "backend error: unknown name " + name })
    }
    Result::Ok(env[index].value)
}

func add_values(Value left, Value right) Result[Value, backend_error] {
    switch left {
        Value.Int(left_int) : {
            switch right {
                Value.Int(right_int) : Result::Ok(Value.Int(left_int + right_int)),
                _ : Result::Err(backend_error { message: "backend error: + expects matching types" }),
            }
        }
        Value.String(left_text) : {
            switch right {
                Value.String(right_text) : Result::Ok(Value.String(left_text + right_text)),
                _ : Result::Err(backend_error { message: "backend error: + expects matching string types" }),
            }
        }
        _ : Result::Err(backend_error { message: "backend error: unsupported + operands" }),
    }
}

func numeric_binary(Value left, Value right, string op) Result[Value, backend_error] {
    switch left {
        Value.Int(left_int) : {
            switch right {
                Value.Int(right_int) : {
                    if op == "-" {
                        Result::Ok(Value.Int(left_int - right_int))
                    } else if op == "*" {
                        Result::Ok(Value.Int(left_int * right_int))
                    } else if op == "/" {
                        if right_int == 0 {
                            Result::Err(backend_error { message: "backend error: division by zero" })
                        } else {
                            Result::Ok(Value.Int(left_int / right_int))
                        }
                    } else {
                        Result::Err(backend_error { message: "backend error: unsupported numeric operator " + op })
                    }
                }
                _ : Result::Err(backend_error { message: "backend error: numeric operator expects int32 operands" }),
            }
        }
        _ : Result::Err(backend_error { message: "backend error: numeric operator expects int32 operands" }),
    }
}

func compare_values(Value left, Value right, bool equal) Result[Value, backend_error] {
    var same = false
    switch left {
        Value.Int(left_int) : {
            switch right {
                Value.Int(right_int) : same = left_int == right_int,
                _ : Result::Err(backend_error { message: "backend error: comparison expects matching types" }),
            }
        }
        Value.String(left_text) : {
            switch right {
                Value.String(right_text) : same = left_text == right_text,
                _ : Result::Err(backend_error { message: "backend error: comparison expects matching types" }),
            }
        }
        Value.Bool(left_bool) : {
            switch right {
                Value.Bool(right_bool) : same = left_bool == right_bool,
                _ : Result::Err(backend_error { message: "backend error: comparison expects matching types" }),
            }
        }
        Value.Unit(_) : {
            switch right {
                Value.Unit(_) : same = true,
                _ : Result::Err(backend_error { message: "backend error: comparison expects matching types" }),
            }
        }
    }

    if equal {
        Result::Ok(Value.Bool(same))
    } else {
        Result::Ok(Value.Bool(!same))
    }
}

func ordered_compare(Value left, Value right, string op) Result[Value, backend_error] {
    switch left {
        Value.Int(left_int) : {
            switch right {
                Value.Int(right_int) : {
                    if op == "<" {
                        Result::Ok(Value.Bool(left_int < right_int))
                    } else if op == "<=" {
                        Result::Ok(Value.Bool(left_int <= right_int))
                    } else if op == ">" {
                        Result::Ok(Value.Bool(left_int > right_int))
                    } else if op == ">=" {
                        Result::Ok(Value.Bool(left_int >= right_int))
                    } else {
                        Result::Err(backend_error { message: "backend error: unsupported ordered comparison " + op })
                    }
                }
                _ : Result::Err(backend_error { message: "backend error: ordered comparison expects int32 operands" }),
            }
        }
        _ : Result::Err(backend_error { message: "backend error: ordered comparison expects int32 operands" }),
    }
}

func logical_binary(Value left, Value right, bool and_op) Result[Value, backend_error] {
    switch left {
        Value.Bool(left_bool) : {
            switch right {
                Value.Bool(right_bool) : {
                    if and_op {
                        Result::Ok(Value.Bool(left_bool && right_bool))
                    } else {
                        Result::Ok(Value.Bool(left_bool || right_bool))
                    }
                }
                _ : Result::Err(backend_error { message: "backend error: logical operator expects bool operands" }),
            }
        }
        _ : Result::Err(backend_error { message: "backend error: logical operator expects bool operands" }),
    }
}

func value_to_exit_code(Value value) Result[int32, backend_error] {
    switch value {
        Value.Int(number) : Result::Ok(number),
        Value.Bool(flag) : Result::Ok(if flag { 1 } else { 0 }),
        Value.Unit(_) : Result::Ok(0),
        Value.String(_) : Result::Err(backend_error { message: "backend error: main cannot return string" }),
    }
}

func stringify_value(Value value) string {
    switch value {
        Value.Int(number) : to_string(number),
        Value.String(text) : text,
        Value.Bool(flag) : if flag { "true" } else { "false" },
        Value.Unit(_) : "()",
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

func emit_asm(Vec[write_op] writes, int32 exit_code) string {
    var data_lines = Vec[string]()
    var text_lines = Vec[string]()
    data_lines.push(".section .data")
    text_lines.push(".section .text")
    text_lines.push(".global _start")
    text_lines.push("_start:")

    var message_index = 0
    var i = 0
    while i < writes.len() {
        append_write_op(data_lines, text_lines, writes[i], message_index)
        message_index = message_index + 1
        i = i + 1
    }

    text_lines.push("    mov $60, %rax")
    text_lines.push("    mov $" + to_string(exit_code) + ", %rdi")
    text_lines.push("    syscall")

    join_lines(data_lines) + "\n\n" + join_lines(text_lines) + "\n"
}

func append_write_op(Vec[string] data_lines, Vec[string] text_lines, write_op op, int32 index) () {
    var label = "message_" + to_string(index)
    data_lines.push(label + ":")
    data_lines.push("    .ascii \"" + escape_asm_string(op.text) + "\"")
    text_lines.push("    mov $1, %rax")
    text_lines.push("    mov $" + to_string(op.fd) + ", %rdi")
    text_lines.push("    lea " + label + "(%rip), %rsi")
    text_lines.push("    mov $" + to_string(len(op.text)) + ", %rdx")
    text_lines.push("    syscall")
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

func copy_bindings(Vec[Binding] source) Vec[Binding] {
    var out = Vec[Binding]()
    var i = 0
    while i < source.len() {
        out.push(source[i])
        i = i + 1
    }
    out
}

func find_binding_index(Vec[Binding] env, string name) int32 {
    var i = env.len()
    while i > 0 {
        i = i - 1
        if env[i].name == name {
            return i
        }
    }
    -1
}

func propagate_bindings(Vec[Binding] mut outer, Vec[Binding] inner) () {
    var i = 0
    while i < inner.len() {
        var index = find_binding_index(outer, inner[i].name)
        if index >= 0 {
            outer.set(index, inner[i])
        }
        i = i + 1
    }
}

func join_lines(Vec[string] lines) string {
    join_with(lines, "\n")
}

func join_with(Vec[string] values, string sep) string {
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
