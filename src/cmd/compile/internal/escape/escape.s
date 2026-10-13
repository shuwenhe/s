package compile.internal.escape

import (
    "compile.internal.base"
    "compile.internal.ir"
    "compile.internal.types"
    "compile.internal.typecheck"
)

enum esc_level {
    esc_unknown,
    esc_func_planned,
    esc_func_started,
    esc_func_tagged,
}

enum label_state {
    looping,
    nonlooping,
}

enum attr_type {
    attr_escapes,
    attr_persists,
    attr_mutates,
    attr_calls,
}

struct location {
    ir.node n
    ir.func curfn
    int result_index
    bool captured
    bool addrtaken
    bool reassigned
    vec[attr_type] attrs
}

struct closure_info {
    ir.node k
    ir.closure_expr clo
}

struct batch {
    vec[location] all_locs
    vec[closure_info] closures
    location heap_loc
    location mutator_loc
    location callee_loc
    location blank_loc
}

struct escape_analyzer {
    batch* b
    ir.func curfn
    int loop_depth
}

func funcs(all_fns: vec[ir.func]) {
    b := batch {
        all_locs: vec[location](),
        closures: vec[closure_info](),
        heap_loc: location {
            n: nil,
            curfn: nil,
            result_index: 0,
            captured: false,
            addrtaken: false,
            reassigned: false,
            attrs: vec[attr_type](),
        },
        mutator_loc: location {
            n: nil,
            curfn: nil,
            result_index: 0,
            captured: false,
            addrtaken: false,
            reassigned: false,
            attrs: vec[attr_type](),
        },
        callee_loc: location {
            n: nil,
            curfn: nil,
            result_index: 0,
            captured: false,
            addrtaken: false,
            reassigned: false,
            attrs: vec[attr_type](),
        },
        blank_loc: location {
            n: nil,
            curfn: nil,
            result_index: 0,
            captured: false,
            addrtaken: false,
            reassigned: false,
            attrs: vec[attr_type](),
        },
    }
    
    for fn in all_fns {
        batch_init_func(&b, fn)
    }
    
    for fn in all_fns {
        if !ir.is_closure(fn) {
            batch_walk_func(&b, fn)
        }
    }
    
    for closure_item in &b.closures {
        batch_flow_closure(&b, closure_item.k, closure_item.clo)
    }
    
    batch_finish(&b, all_fns)
}

func batch_init_func(b: batch*, fn: ir.func) {
    if base.debug_flag() {
        base.warn("escape analysis initializing function")
    }
    
    dcl_list := ir.func_decls(fn)
    for dcl in dcl_list {
        _ = new_location(b, dcl, true)
    }
    
    closure_vars := ir.func_closure_vars(fn)
    for cv in closure_vars {
        _ = new_location(b, cv, true)
    }
    
    results := ir.func_results(fn)
    for i in 0..results.len() {
        res := results[i]
        loc := old_location(b, res)
        if loc != nil {
            loc.result_index = 1 + i
        }
    }
}

func batch_walk_func(b: batch*, fn: ir.func) {
    e := escape_analyzer {
        b: b,
        curfn: fn,
        loop_depth: 1,
    }
    
    body := ir.func_body(fn)
    escape_block(&e, &body)
}

func batch_flow_closure(b: batch*, k: ir.node, clo: ir.closure_expr) {
    func_def := ir.closure_func(clo)
    if func_def == nil {
        return
    }
    
    closure_vars := ir.func_closure_vars(func_def)
    
    for cv in closure_vars {
        loc := old_location(b, cv)
        if loc == nil {
            continue
        }
        
        if !loc.captured {
            base.fatal("closure variable never captured")
        }
        
        cv_type := ir.node_type(ir.as_node(cv))
        cv_size := types.type_size(cv_type)
        
        if !loc.addrtaken && !loc.reassigned && cv_size <= 128 {
            ir.set_byval(cv, true)
        } else {
            ir.set_byval(cv, false)
            ir.set_addrtaken(cv, true)
        }
        
        if base.debug_flag_lower_m() > 1 {
            how := "ref"
            if ir.is_byval(cv) {
                how = "value"
            }
            base.warn_at(ir.node_pos(ir.as_node(cv)), "capturing by " + how)
        }
    }
}

func batch_finish(b: batch*, fns: vec[ir.func]) {
    for fn in fns {
        ir.set_esc(fn, esc_func_tagged)
        
        params := ir.func_params(fn)
        for i in 0..params.len() {
            param := params[i]
            tag := batch_param_tag(b, fn, 1 + i, param)
            ir.set_param_note(param, tag)
        }
    }
    
    for loc in &b.all_locs {
        n := loc.n
        if n == nil {
            continue
        }
        
        if ir.node_op(n) == "name" {
            ir.set_opt(n, nil)
        }
        
        has_escapes := location_has_attr(loc, attr_escapes)
        
        if has_escapes {
            if ir.node_op(n) == "name" {
                if base.is_runtime_flag() {
                    base.error_at(ir.node_pos(n), "escapes to heap, not allowed in runtime")
                }
                if base.debug_flag_lower_m() != 0 {
                    base.warn_at(ir.node_pos(n), "moved to heap")
                }
            } else {
                if base.debug_flag_lower_m() != 0 {
                    base.warn_at(ir.node_pos(n), "escapes to heap")
                }
            }
            ir.set_esc(n, ir.esc_heap)
        } else {
            if base.debug_flag_lower_m() != 0 && ir.node_op(n) != "name" {
                base.warn_at(ir.node_pos(n), "does not escape")
            }
            ir.set_esc(n, ir.esc_none)
            
            if !location_has_attr(loc, attr_persists) {
                node_op := ir.node_op(n)
                if node_op == "closure" {
                    closure_expr := ir.as_closure_expr(n)
                    if closure_expr != nil {
                        ir.set_transient(closure_expr, true)
                    }
                }
            }
        }
    }
}

func batch_param_tag(b: batch*, fn: ir.func, narg: int, f: ir.param) string {
    if ir.func_body_len(fn) == 0 {
        param_type := ir.param_type(f)
        
        if types.type_is_uintptr(param_type) {
            if base.debug_flag_lower_m() != 0 {
                base.warn("assuming parameter is unsafe uintptr")
            }
            return ""
        }
        
        if !types.type_has_pointers(param_type) {
            return ""
        }
    }
    
    "~r0"
}

func escape_block(e: escape_analyzer*, stmts: vec[ir.node]*) {
    for stmt in stmts {
        escape_stmt(e, stmt)
    }
}

func escape_stmt(e: escape_analyzer*, n: ir.node) {
    if n == nil {
        return
    }
    
    node_op := ir.node_op(n)
    
    if node_op == "for" {
        for_stmt := ir.as_for_stmt(n)
        if for_stmt != nil {
            old_loop := e.loop_depth
            e.loop_depth = e.loop_depth + 1
            
            init := ir.for_init(for_stmt)
            if init != nil {
                escape_stmt(e, init)
            }
            
            cond := ir.for_cond(for_stmt)
            if cond != nil {
                escape_expr(e, cond)
            }
            
            body := ir.for_body(for_stmt)
            escape_block(e, &body)
            
            step := ir.for_step(for_stmt)
            if step != nil {
                escape_stmt(e, step)
            }
            
            e.loop_depth = old_loop
        }
        return
    }
    
    if node_op == "if" {
        if_stmt := ir.as_if_stmt(n)
        if if_stmt != nil {
            cond := ir.if_cond(if_stmt)
            escape_expr(e, cond)
            
            then_body := ir.if_body(if_stmt)
            escape_block(e, &then_body)
            
            else_body := ir.if_else(if_stmt)
            escape_block(e, &else_body)
        }
        return
    }
    
    if node_op == "assign" {
        assign_stmt := ir.as_assign_stmt(n)
        if assign_stmt != nil {
            lhs := ir.assign_lhs(assign_stmt)
            rhs := ir.assign_rhs(assign_stmt)
            
            escape_expr(e, lhs)
            escape_expr(e, rhs)
        }
        return
    }
    
    if node_op == "call" {
        escape_expr(e, n)
        return
    }
    
    if node_op == "block" {
        block_stmt := ir.as_block_stmt(n)
        if block_stmt != nil {
            stmts_list := ir.block_list(block_stmt)
            escape_block(e, &stmts_list)
        }
        return
    }
}

func escape_expr(e: escape_analyzer*, n: ir.node) {
    if n == nil {
        return
    }
    
    node_op := ir.node_op(n)
    
    if node_op == "call" {
        call_expr := ir.as_call_expr(n)
        if call_expr != nil {
            fun := ir.call_fun(call_expr)
            if fun != nil {
                escape_expr(e, fun)
            }
            
            args := ir.call_args(call_expr)
            for arg in args {
                escape_expr(e, arg)
            }
        }
        return
    }
    
    if node_op == "member" {
        member_expr := ir.as_member_expr(n)
        if member_expr != nil {
            target := ir.member_target(member_expr)
            escape_expr(e, target)
        }
        return
    }
    
    if node_op == "index" {
        index_expr := ir.as_index_expr(n)
        if index_expr != nil {
            target := ir.index_target(index_expr)
            index := ir.index_expr_index(index_expr)
            escape_expr(e, target)
            escape_expr(e, index)
        }
        return
    }
    
    if node_op == "addr" {
        addr_expr := ir.as_addr_expr(n)
        if addr_expr != nil {
            target := ir.addr_target(addr_expr)
            escape_expr(e, target)
        }
        return
    }
}

func new_location(b: batch*, n: ir.node, stack_only: bool) option[location] {
    loc := location {
        n: n,
        curfn: nil,
        result_index: 0,
        captured: false,
        addrtaken: false,
        reassigned: false,
        attrs: vec[attr_type](),
    }
    
    b.all_locs.push(loc)
    option::some(loc)
}

func old_location(b: batch*, n: ir.node) location* {
    for i in 0..b.all_locs.len() {
        loc_n := b.all_locs[i].n
        if loc_n != nil && ir.nodes_equal(loc_n, n) {
            return &b.all_locs[i]
        }
    }
    &b.blank_loc
}

func location_has_attr(loc: location*, a: attr_type) bool {
    for attr_item in &loc.attrs {
        if attr_item == a {
            return true
        }
    }
    false
}

func location_add_attr(loc: location*, a: attr_type) {
    if !location_has_attr(loc, a) {
        loc.attrs.push(a)
    }
}
