package compile.internal.bloop

import (
    "compile.internal.base"
    "compile.internal.ir"
    "compile.internal.typecheck"
    "compile.internal.types"
    "std.io"
    "std.result"
    "std.strings"
)

struct keep_alive_info {
    vec[string] names
    vec[ir.node] nodes
    bool has_ignored
}

struct bloop_editor {
    bool in_bloop
    ir.func cur_fn
}

func get_name_from_node(node: ir.node) option[ir.name] {
    current := node
    
    while current != nil {
        node_op := ir.node_op(current)
        
        switch node_op {
            "name" : {
                return option.some(ir.as_name(current))
            }
            
            "slice" | "slice3" : {
                current = ir.slice_elem(current)
            }
            
            "member" : {
                current = ir.member_target(current)
            }
            
            "convert" | "convert_iface" | "convert_nop" : {
                current = ir.convert_target(current)
            }
            
            "addr" : {
                current = ir.addr_target(current)
            }
            
            "member_ptr" : {
                current = ir.member_target(current)
            }
            
            "index" | "index_map" : {
                current = ir.index_target(current)
            }
            
            default : {
                current = nil
            }
        }
    }
    
    option.none
}

func is_ignored_name(name: ir.name) bool {
    if name == nil {
        return false
    }
    
    sym := ir.name_sym(name)
    if sym == nil {
        return false
    }
    
    sym_name := ir.sym_name(sym)
    if sym_name.len() == 0 {
        return false
    }
    
    sym_name[0] == '#'
}

func is_ignored_call(call: ir.call_expr) bool {
    fun := ir.call_fun(call)
    if fun == nil {
        return false
    }
    
    name := ir.as_name_if(fun)
    if name == nil {
        return false
    }
    
    if !ir.is_func_name(name) {
        return false
    }
    
    sym := ir.name_sym(name)
    if sym == nil {
        return false
    }
    
    sym_name := ir.sym_name(sym)
    sym_pkg := ir.sym_pkg(sym)
    
    (sym_name == "panicrangestate" || sym_name == "KeepAlive") &&
    ir.is_runtime_pkg(sym_pkg)
}

func get_addressable_name_from_node(node: ir.node) (option[ir.name], bool) {
    name_opt := get_name_from_node(node)
    
    switch name_opt {
        option.some(n) : {
            ignored := is_ignored_name(n)
            
            if !ir.is_addressable(n) {
                return (option.none, ignored)
            }
            
            return (option.some(n), ignored)
        }
        
        option.none : {
            return (option.none, false)
        }
    }
}

func get_keep_alive_nodes(pos: ir.src_pos, node: ir.node) vec[ir.node] {
    keep_alive_nodes := vec[ir.node]()
    
    name_opt, ignored := get_addressable_name_from_node(node)
    
    if ignored {
        return keep_alive_nodes
    }
    
    switch name_opt {
        option.some(name) : {
            debug_name(name, pos)
            keep_alive_nodes.push(ir.as_node(name))
            return keep_alive_nodes
        }
        
        option.none : {
            deref := ir.as_deref_if(node)
            if deref != nil {
                if base.debug_flag_lower_m() > 1 {
                    base.warn_at(pos, "dereference will be kept alive")
                }
                keep_alive_nodes.push(deref)
                return keep_alive_nodes
            }
            
            if base.debug_flag_lower_m() > 1 {
                base.warn_at(pos, "expr is unknown to bloop pass")
            }
            
            return keep_alive_nodes
        }
    }
}

func keep_alive_at(curfunc: ir.func, nodes: vec[ir.node], cur_node: ir.node) ir.node {
    if nodes.len() == 0 {
        return cur_node
    }
    
    pos := ir.node_pos(cur_node)
    stmts := vec[ir.node]()
    stmts.push(cur_node)
    
    for node in nodes {
        if node == nil {
            continue
        }
        
        sym := ir.node_sym(node)
        if sym == nil || ir.is_blank_sym(sym) {
            continue
        }
        
        if !ir.is_addressable(node) {
            base.fatal_at(ir.node_pos(node), "keepAliveAt: node is not addressable")
        }
        
        arg := ir.new_convert_expr(pos, ir.OCONV, types.unsafe_ptr_type(), typecheck.node_addr(curfunc, node))
        call_expr := typecheck.call(curfunc, pos, typecheck.lookup_runtime("KeepAlive"), vec.from_array([arg]), false)
        
        ir.mark_compiler_var_live(call_expr)
        ir.mark_no_inline(call_expr)
        
        stmts.push(call_expr)
    }
    
    ir.new_block_stmt(pos, stmts)
}

func debug_name(name: ir.name, pos: ir.src_pos) {
    if base.debug_flag_lower_m() > 1 {
        linksym := ir.name_linksym(name)
        if linksym != nil {
            sym_name := ir.linksym_name(linksym)
            base.warn_at(pos, sym_name + " will be kept alive")
        } else {
            base.warn_at(pos, "expr will be kept alive")
        }
    }
}

func preserve_call_results(curfn: ir.func, call: ir.call_expr) ir.node {
    keep_alive_nodes := vec[ir.node]()
    
    fun_type := ir.call_fun_type(call)
    num_results := ir.type_num_results(fun_type)
    
    results := vec[ir.node]()
    for i in 0..num_results {
        res_type := ir.type_result_at(fun_type, i)
        tmp := typecheck.temp_at(ir.node_pos(call), curfn, res_type)
        results.push(tmp)
        keep_alive_nodes.push(tmp)
    }
    
    if base.debug_flag_lower_m() > 1 {
        plural := ""
        if num_results > 1 {
            plural = "s"
        }
        base.warn_at(ir.node_pos(call), "function result" + plural + " will be kept alive")
    }
    
    assign := typecheck.assign_expr(curfn, ir.new_assign_list_stmt(ir.node_pos(call), ir.OAS2, results, vec.from_array([call])))
    ir.mark_def(assign)
    
    for tmp in results {
        init_list := ir.assign_init_list(assign)
        decl := ir.new_decl(ir.node_pos(assign), ir.ODCL, tmp)
        init_list.push(typecheck.stmt(curfn, decl))
    }
    
    keep_alive_at(curfn, keep_alive_nodes, assign)
}

func preserve_call_args(curfn: ir.func, call: ir.call_expr) ir.node {
    arg_tmps := vec[ir.node]()
    keep_alive_nodes := vec[ir.node]()
    
    call_args := ir.call_args(call)
    
    for i in 0..call_args.len() {
        arg := call_args[i]
        
        name_opt, ignored := get_addressable_name_from_node(arg)
        
        if ignored {
            continue
        }
        
        switch name_opt {
            option.some(name) : {
                debug_name(name, ir.node_pos(call))
                keep_alive_nodes.push(ir.as_node(name))
            }
            
            option.none : {
                if ir.node_op(arg) == "slice_lit" {
                    elements := ir.comp_lit_list(arg)
                    for j in 0..elements.len() {
                        elem := elements[j]
                        elem_name_opt, elem_ignored := get_addressable_name_from_node(elem)
                        
                        if elem_ignored {
                            continue
                        }
                        
                        switch elem_name_opt {
                            option.some(elem_name) : {
                                debug_name(elem_name, ir.node_pos(call))
                                keep_alive_nodes.push(ir.as_node(elem_name))
                            }
                            
                            option.none : {
                                pos := ir.node_pos(elem)
                                tmp := typecheck.temp_at(pos, curfn, ir.node_type(elem))
                                assign := ir.new_assign_stmt(pos, tmp, elem)
                                ir.mark_def(assign)
                                init_list := ir.assign_init_list(assign)
                                decl := ir.new_decl(pos, ir.ODCL, tmp)
                                init_list.push(typecheck.stmt(curfn, decl))
                                
                                arg_tmps.push(typecheck.assign_expr(curfn, assign))
                                
                                elements[j] = tmp
                                
                                if base.debug_flag_lower_m() > 1 {
                                    base.warn_at(ir.node_pos(call), "function arg will be kept alive")
                                }
                            }
                        }
                    }
                } else {
                    pos := ir.node_pos(call)
                    tmp := typecheck.temp_at(pos, curfn, ir.node_type(arg))
                    assign := ir.new_assign_stmt(pos, tmp, arg)
                    ir.mark_def(assign)
                    init_list := ir.assign_init_list(assign)
                    decl := ir.new_decl(pos, ir.ODCL, tmp)
                    init_list.push(typecheck.stmt(curfn, decl))
                    
                    arg_tmps.push(typecheck.assign_expr(curfn, assign))
                    keep_alive_nodes.push(tmp)
                    
                    call_args[i] = tmp
                    
                    if base.debug_flag_lower_m() > 1 {
                        base.warn_at(ir.node_pos(call), "function arg will be kept alive")
                    }
                }
            }
        }
    }
    
    if arg_tmps.len() > 0 {
        arg_tmps.push(call)
        return keep_alive_at(curfn, keep_alive_nodes, ir.new_block_stmt(ir.node_pos(call), arg_tmps))
    }
    
    keep_alive_at(curfn, keep_alive_nodes, call)
}

func preserve_stmt(curfn: ir.func, stmt: ir.node) ir.node {
    stmt_op := ir.node_op(stmt)
    
    switch stmt_op {
        "assign" : {
            lhs := ir.assign_lhs(stmt)
            if ir.is_blank(lhs) {
                rhs := ir.assign_rhs(stmt)
                tmp := typecheck.temp_at(ir.node_pos(stmt), curfn, ir.node_type(rhs))
                ir.set_assign_lhs(stmt, tmp)
                ir.mark_def(stmt)
                
                init_list := ir.assign_init_list(stmt)
                decl := ir.new_decl(ir.node_pos(stmt), ir.ODCL, tmp)
                init_list.push(typecheck.stmt(curfn, decl))
                
                stmt = typecheck.assign_expr(curfn, stmt)
                lhs = ir.assign_lhs(stmt)
            }
            
            keep_alive_nodes := get_keep_alive_nodes(ir.node_pos(stmt), lhs)
            return keep_alive_at(curfn, keep_alive_nodes, stmt)
        }
        
        "assign_list" : {
            keep_alive_nodes := vec[ir.node]()
            has_blank := false
            
            lhs_list := ir.assign_list_lhs(stmt)
            rhs_list := ir.assign_list_rhs(stmt)
            
            for i in 0..lhs_list.len() {
                lhs := lhs_list[i]
                
                if ir.is_blank(lhs) {
                    rhs_type := ir.node_type(rhs_list[i])
                    tmp := typecheck.temp_at(ir.node_pos(stmt), curfn, rhs_type)
                    lhs_list[i] = tmp
                    
                    init_list := ir.assign_init_list(stmt)
                    decl := ir.new_decl(ir.node_pos(stmt), ir.ODCL, tmp)
                    init_list.push(typecheck.stmt(curfn, decl))
                    
                    has_blank = true
                }
                
                keep_alive_nodes = append_keep_alive(keep_alive_nodes, get_keep_alive_nodes(ir.node_pos(stmt), lhs))
            }
            
            if has_blank {
                ir.mark_def(stmt)
                stmt = typecheck.assign_expr(curfn, stmt)
            }
            
            return keep_alive_at(curfn, keep_alive_nodes, stmt)
        }
        
        "assign_op" : {
            lhs := ir.assign_op_lhs(stmt)
            keep_alive_nodes := get_keep_alive_nodes(ir.node_pos(stmt), lhs)
            return keep_alive_at(curfn, keep_alive_nodes, stmt)
        }
        
        "call" : {
            call_expr := ir.as_call_expr(stmt)
            
            if is_ignored_call(call_expr) {
                return stmt
            }
            
            fun := ir.call_fun(call_expr)
            if fun != nil {
                fun_type := ir.call_fun_type(call_expr)
                if ir.type_num_results(fun_type) != 0 {
                    return preserve_call_results(curfn, call_expr)
                }
            }
            
            return preserve_call_args(curfn, call_expr)
        }
        
        default : {
            return stmt
        }
    }
}

func preserve_stmts(curfn: ir.func, stmts: &vec[ir.node]) {
    for i in 0..stmts.len() {
        stmts[i] = preserve_stmt(curfn, stmts[i])
    }
}

func is_testing_bloop(node: ir.node) bool {
    if ir.node_op(node) != "for" {
        return false
    }
    
    for_stmt := ir.as_for_stmt(node)
    if for_stmt == nil {
        return false
    }
    
    cond := ir.for_cond(for_stmt)
    if cond == nil || ir.node_op(cond) != "call" {
        return false
    }
    
    call_expr := ir.as_call_expr(cond)
    fun := ir.call_fun(call_expr)
    if fun == nil || ir.node_op(fun) != "method" {
        return false
    }
    
    name := ir.method_name(fun)
    if name == nil {
        return false
    }
    
    sym := ir.name_sym(name)
    if sym == nil {
        return false
    }
    
    sym_name := ir.sym_name(sym)
    sym_pkg := ir.sym_pkg(sym)
    
    (sym_name == "(*B).Loop") &&
    ir.is_func_class(name) &&
    ir.is_testing_pkg(sym_pkg)
}

func edit_bloop(editor: &bloop_editor, node: ir.node) ir.node {
    editor.in_bloop = is_testing_bloop(node) || editor.in_bloop
    
    ir.edit_children(node, |child| { edit_bloop(editor, child) })
    
    if editor.in_bloop {
        node_op := ir.node_op(node)
        
        switch node_op {
            "for" : {
                for_stmt := ir.as_for_stmt(node)
                body := ir.for_body(for_stmt)
                preserve_stmts(editor.cur_fn, &body)
            }
            
            "if" : {
                if_stmt := ir.as_if_stmt(node)
                body := ir.if_body(if_stmt)
                else_body := ir.if_else(if_stmt)
                preserve_stmts(editor.cur_fn, &body)
                preserve_stmts(editor.cur_fn, &else_body)
            }
            
            "block" : {
                block_stmt := ir.as_block_stmt(node)
                stmts := ir.block_list(block_stmt)
                preserve_stmts(editor.cur_fn, &stmts)
            }
            
            "case" : {
                case_clause := ir.as_case_clause(node)
                body := ir.case_body(case_clause)
                preserve_stmts(editor.cur_fn, &body)
            }
            
            "comm" : {
                comm_clause := ir.as_comm_clause(node)
                body := ir.comm_body(comm_clause)
                preserve_stmts(editor.cur_fn, &body)
            }
            
            "range" : {
                range_stmt := ir.as_range_stmt(node)
                body := ir.range_body(range_stmt)
                preserve_stmts(editor.cur_fn, &body)
            }
            
            "closure" : {
                closure := ir.as_closure(node)
                closure_fn := ir.closure_func(closure)
                if closure_fn != nil {
                    old_fn := editor.cur_fn
                    editor.cur_fn = closure_fn
                    
                    closure_body := ir.func_body(closure_fn)
                    preserve_stmts(editor.cur_fn, &closure_body)
                    
                    editor.cur_fn = old_fn
                }
            }
            
            default : {}
        }
    }
    
    node
}

func walk(pkg: ir.package) {
    funcs := ir.pkg_funcs(pkg)
    
    for func in funcs {
        editor := bloop_editor {
            in_bloop: false,
            cur_fn: func,
        }
        
        func_body := ir.func_body(func)
        for i in 0..func_body.len() {
            func_body[i] = edit_bloop(&editor, func_body[i])
        }
    }
}

func append_keep_alive(acc: vec[ir.node], new: vec[ir.node]) vec[ir.node] {
    for node in new {
        acc.push(node)
    }
    acc
}

func edit_expr(expr value, bool in_bloop) expr {
    switch value {
        expr.borrow(borrow_value) : expr.borrow(borrow_expr {
            target: std.prelude.box(edit_expr(borrow_value.target.value, in_bloop)), mutable borrow_value.mutable, inferred_type borrow_value.inferred_type,
        }),
        expr.member(member_value) : expr.member(member_expr {
            target: std.prelude.box(edit_expr(member_value.target.value, in_bloop)), member member_value.member, inferred_type member_value.inferred_type,
        }),
        expr.index(index_value) : expr.index(index_expr {
            target: std.prelude.box(edit_expr(index_value.target.value, in_bloop)), index std.prelude.box(edit_expr(index_value.index.value, in_bloop)), inferred_type index_value.inferred_type,
        }),
        expr.call(call_value) : {
            out_args := expr[]()
            i := 0
            for i < std.prelude.len(call_value.args) {
                out_args = append(out_args, edit_expr(call_value.args[i], in_bloop))
                i = i + 1
            }
            expr.call(call_expr {
                callee: std.prelude.box(edit_expr(call_value.callee.value, in_bloop)), args out_args, inferred_type call_value.inferred_type, resolved_callee call_value.resolved_callee, type_args call_value.type_args,
            })
        }
        expr.if(if_value) : {
            then_block := edit_block(if_value.then_branch, in_bloop)
            else_expr := option.none
            switch if_value.else_branch {
                option.some(else_value) : {
                    else_expr = option.some(std.prelude.box(edit_expr(else_value.value, in_bloop)))
                }
                option.none : (),
            }
            expr.if(if_expr {
                condition: std.prelude.box(edit_expr(if_value.condition.value, in_bloop)), then_branch then_block, else_branch else_expr, inferred_type if_value.inferred_type,
            })
        }
        expr.while(while_value) : {
            loop_flag := in_bloop || is_testing_bloop_expr(while_value.condition.value)
            expr.while(while_expr {
                condition: std.prelude.box(edit_expr(while_value.condition.value, in_bloop)), body: edit_block(while_value.body, loop_flag), inferred_type: while_value.inferred_type,
            })
        }
        expr.for(for_value) : {
            init := for_value.init
            condition := for_value.condition
            post := for_value.post
            iterable := for_value.iterable
            if init.is_some() { init = option.some(std.prelude.box(edit_stmt(init.unwrap().value, in_bloop))) }
            if condition.is_some() { condition = option.some(std.prelude.box(edit_expr(condition.unwrap().value, in_bloop))) }
            if post.is_some() { post = option.some(std.prelude.box(edit_stmt(post.unwrap().value, in_bloop))) }
            if iterable.is_some() { iterable = option.some(std.prelude.box(edit_expr(iterable.unwrap().value, in_bloop))) }
            expr.for(for_expr {
                init: init, condition: condition, post: post, names: for_value.names,
                iterable: iterable, body: edit_block(for_value.body, in_bloop), inferred_type: for_value.inferred_type,
            })
        }
        expr.block(block_value) : expr.block(edit_block(block_value, in_bloop)),
        expr.switch(switch_value) : {
            arms := switch_arm[]()
            i := 0
            for i < std.prelude.len(switch_value.arms) {
                arms.push(switch_arm {
                    pattern: switch_value.arms[i].pattern, expr edit_expr(switch_value.arms[i].expr, in_bloop),
                })
                i = i + 1
            }
            expr.switch(switch_expr {
                subject: std.prelude.box(edit_expr(switch_value.subject.value, in_bloop)), arms arms, inferred_type switch_value.inferred_type,
            })
        }
        _ : value,
    }
}

func edit_stmt(stmt value, bool in_bloop) stmt {
    switch value {
        stmt.c_for(loop_value) : {
            loop_flag := in_bloop || is_testing_bloop_expr(loop_value.condition)
            stmt.c_for(c_for_stmt {
                init: std.prelude.box(edit_stmt(loop_value.init.value, in_bloop)), condition edit_expr(loop_value.condition, in_bloop), step std.prelude.box(edit_stmt(loop_value.step.value, in_bloop)), body edit_block(loop_value.body, loop_flag),
            })
        }
        stmt.let(var_value) : stmt.let(var_stmt {
            name: var_value.name, type_name var_value.type_name, value edit_expr(var_value.value, in_bloop),
        }),
        stmt.expr(expr_value) : stmt.s.expr(expr_stmt {
            expr: edit_expr(expr_value.expr, in_bloop),
        }),
        _ : value,
    }
}

func edit_block(block_expr block_value, bool in_bloop) block_expr {
    out_stmts := stmt[]()
    i := 0
    for i < std.prelude.len(block_value.statements) {
        current := edit_stmt(block_value.statements[i], in_bloop)
        out_stmts = append(out_stmts, current)
        if in_bloop {
            extra := preserve_stmt(current)
            j := 0
            for j < std.prelude.len(extra) {
                out_stmts = append(out_stmts, extra[j])
                j = j + 1
            }
        }
        i = i + 1
    }
    final_expr := option.none
    switch block_value.final_expr {
        option.some(final_value) : final_expr = option.some(edit_expr(final_value, in_bloop)),
        option.none : (),
    }
    block_expr {
        statements: out_stmts, final_expr final_expr, inferred_type block_value.inferred_type,
    }
}

func has_testing_import(source_file pkg) bool {
    i := 0
    for i < std.prelude.len(pkg.uses) {
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
    out_items := item[]()
    i := 0
    for i < std.prelude.len(pkg.items) {
        switch pkg.items[i] {
            item.function(fn_value) : {
                out_fn := fn_value
                switch out_fn.body {
                    option.some(body_value) : {
                        out_fn.body = option.some(edit_block(body_value, false))
                    }
                    option.none : (),
                }
                out_items = append(out_items, item.function(out_fn))
            }
            _ : out_items = append(out_items, pkg.items[i]),
        }
        i = i + 1
    }
    source_file {
        pkg: pkg.pkg, uses pkg.uses, items out_items,
    }
}

func starts_with(string text, string prefix) bool {
    if std.prelude.len(text) < std.prelude.len(prefix) {
        return false
    }
    std.prelude.slice(text, 0, std.prelude.len(prefix)) == prefix
}
