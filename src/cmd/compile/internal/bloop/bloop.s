package compile.internal.bloop

use s.block_expr
use s.borrow_expr
use s.call_expr
use s.c_for_stmt
use s.expr
use s.expr_stmt
use s.for_expr
use s.function_decl
use s.if_expr
use s.increment_stmt
use s.index_expr
use s.item
use s.member_expr
use s.name_expr
use s.param
use s.source_file
use s.stmt
use s.switch_arm
use s.switch_expr
use s.var_stmt
use s.while_expr
use std.option.option
use std.prelude.box
use std.prelude.len
use std.prelude.slice
use std.vec.vec

func get_name_from_expr(expr value) option[string] {
    switch value {
        expr.name(name_value) : option::some(name_value.name),
        expr.borrow(borrow_value) : get_name_from_expr(borrow_value.target.value),
        expr.member(member_value) : get_name_from_expr(member_value.target.value),
        expr.index(index_value) : get_name_from_expr(index_value.target.value),
        _ : option::none,
    }
}

func append_unique(vec[string] mut names, string value) () {
    if value == "" || value == "_" {
        return
    }
    let i = 0
    while i < names.len() {
        if names[i] == value {
            return
        }
        i = i + 1
    }
    names.push(value)
}

func collect_call_arg_names(call_expr call_value) vec[string] {
    let out = vec[string]()
    let i = 0
    while i < call_value.args.len() {
        switch get_name_from_expr(call_value.args[i]) {
            option::some(name_value) : append_unique(out, name_value),
            option::none : (),
        }
        i = i + 1
    }
    out
}

func collect_keep_alive_names(stmt value) vec[string] {
    let out = vec[string]()
    switch value {
        stmt.assign(assign_value) : append_unique(out, assign_value.name),
        stmt.increment(increment_value) : append_unique(out, increment_value.name),
        stmt.let(var_value) : append_unique(out, var_value.name),
        stmt.expr(expr_value) : {
            switch expr_value.expr {
                expr.call(call_value) : {
                    let names = collect_call_arg_names(call_value)
                    let i = 0
                    while i < names.len() {
                        append_unique(out, names[i])
                        i = i + 1
                    }
                }
                _ : (),
            }
        }
        _ : (),
    }
    out
}

func keep_alive_stmt(string name_value) stmt {
    let args = vec[expr]()
    args.push(expr::name(name_expr {
        name: name_value,
        inferred_type: option::none,
    }))

    let callee = expr::name(name_expr {
        name: "keep_alive",
        inferred_type: option::none,
    })

    stmt::expr(expr_stmt {
        expr: expr::call(call_expr {
            callee: box(callee),
            args: args,
            inferred_type: option::none,
        }),
    })
}

func preserve_stmt(stmt value) vec[stmt] {
    let out = vec[stmt]()
    let names = collect_keep_alive_names(value)
    let i = 0
    while i < names.len() {
        out.push(keep_alive_stmt(names[i]))
        i = i + 1
    }
    out
}

func is_testing_bloop_expr(expr value) bool {
    switch value {
        expr.call(call_value) : {
            switch call_value.callee.value {
                expr.member(member_value) : {
                    if member_value.member != "Loop" {
                        return false
                    }
                    switch member_value.target.value {
                        expr.name(name_value) : return name_value.name == "b",
                        _ : return false,
                    }
                }
                _ : return false,
            }
        }
        _ : false,
    }
}

func edit_expr(expr value, bool in_bloop) expr {
    switch value {
        expr.borrow(borrow_value) : expr::borrow(borrow_expr {
            target: box(edit_expr(borrow_value.target.value, in_bloop)),
            mutable: borrow_value.mutable,
            inferred_type: borrow_value.inferred_type,
        }),
        expr.member(member_value) : expr::member(member_expr {
            target: box(edit_expr(member_value.target.value, in_bloop)),
            member: member_value.member,
            inferred_type: member_value.inferred_type,
        }),
        expr.index(index_value) : expr::index(index_expr {
            target: box(edit_expr(index_value.target.value, in_bloop)),
            index: box(edit_expr(index_value.index.value, in_bloop)),
            inferred_type: index_value.inferred_type,
        }),
        expr.call(call_value) : {
            let out_args = vec[expr]()
            let i = 0
            while i < call_value.args.len() {
                out_args.push(edit_expr(call_value.args[i], in_bloop))
                i = i + 1
            }
            expr::call(call_expr {
                callee: box(edit_expr(call_value.callee.value, in_bloop)),
                args: out_args,
                inferred_type: call_value.inferred_type,
            })
        }
        expr.if(if_value) : {
            let then_block = edit_block(if_value.then_branch, in_bloop)
            let else_expr = option::none
            switch if_value.else_branch {
                option::some(else_value) : {
                    else_expr = option::some(box(edit_expr(else_value.value, in_bloop)))
                }
                option::none : (),
            }
            expr::if(if_expr {
                condition: box(edit_expr(if_value.condition.value, in_bloop)),
                then_branch: then_block,
                else_branch: else_expr,
                inferred_type: if_value.inferred_type,
            })
        }
        expr.while(while_value) : {
            let loop_flag = in_bloop || is_testing_bloop_expr(while_value.condition.value)
            expr::while(while_expr {
                condition: box(edit_expr(while_value.condition.value, in_bloop)),
                body: edit_block(while_value.body, loop_flag),
                inferred_type: while_value.inferred_type,
            })
        }
        expr.for(for_value) : expr::for(for_expr {
            names: for_value.names,
            declare: for_value.declare,
            iterable: box(edit_expr(for_value.iterable.value, in_bloop)),
            body: edit_block(for_value.body, in_bloop),
            inferred_type: for_value.inferred_type,
        }),
        expr.block(block_value) : expr::block(edit_block(block_value, in_bloop)),
        expr.switch(switch_value) : {
            let arms = vec[switch_arm]()
            let i = 0
            while i < switch_value.arms.len() {
                arms.push(switch_arm {
                    pattern: switch_value.arms[i].pattern,
                    expr: edit_expr(switch_value.arms[i].expr, in_bloop),
                })
                i = i + 1
            }
            expr::switch(switch_expr {
                subject: box(edit_expr(switch_value.subject.value, in_bloop)),
                arms: arms,
                inferred_type: switch_value.inferred_type,
            })
        }
        _ : value,
    }
}

func edit_stmt(stmt value, bool in_bloop) stmt {
    switch value {
        stmt.c_for(loop_value) : {
            let loop_flag = in_bloop || is_testing_bloop_expr(loop_value.condition)
            stmt::c_for(c_for_stmt {
                init: box(edit_stmt(loop_value.init.value, in_bloop)),
                condition: edit_expr(loop_value.condition, in_bloop),
                step: box(edit_stmt(loop_value.step.value, in_bloop)),
                body: edit_block(loop_value.body, loop_flag),
            })
        }
        stmt.let(var_value) : stmt::let(var_stmt {
            name: var_value.name,
            type_name: var_value.type_name,
            value: edit_expr(var_value.value, in_bloop),
        }),
        stmt.expr(expr_value) : stmt::expr(expr_stmt {
            expr: edit_expr(expr_value.expr, in_bloop),
        }),
        _ : value,
    }
}

func edit_block(block_expr block_value, bool in_bloop) block_expr {
    let out_stmts = vec[stmt]()
    let i = 0
    while i < block_value.statements.len() {
        let current = edit_stmt(block_value.statements[i], in_bloop)
        out_stmts.push(current)
        if in_bloop {
            let extra = preserve_stmt(current)
            let j = 0
            while j < extra.len() {
                out_stmts.push(extra[j])
                j = j + 1
            }
        }
        i = i + 1
    }

    let final_expr = option::none
    switch block_value.final_expr {
        option::some(final_value) : final_expr = option::some(edit_expr(final_value, in_bloop)),
        option::none : (),
    }

    block_expr {
        statements: out_stmts,
        final_expr: final_expr,
        inferred_type: block_value.inferred_type,
    }
}

func has_testing_import(source_file pkg) bool {
    let i = 0
    while i < pkg.uses.len() {
        if pkg.uses[i].path == "testing" || starts_with(pkg.uses[i].path, "testing.") {
            return true
        }
        i = i + 1
    }
    false
}

func walk(source_file pkg) source_file {
    if !has_testing_import(pkg) {
        return pkg
    }

    let out_items = vec[item]()
    let i = 0
    while i < pkg.items.len() {
        switch pkg.items[i] {
            item.function(fn_value) : {
                let out_fn = fn_value
                switch out_fn.body {
                    option::some(body_value) : {
                        out_fn.body = option::some(edit_block(body_value, false))
                    }
                    option::none : (),
                }
                out_items.push(item::function(out_fn))
            }
            _ : out_items.push(pkg.items[i]),
        }
        i = i + 1
    }

    source_file {
        pkg: pkg.pkg,
        uses: pkg.uses,
        items: out_items,
    }
}

func starts_with(string text, string prefix) bool {
    if len(text) < len(prefix) {
        return false
    }
    slice(text, 0, len(prefix)) == prefix
}
