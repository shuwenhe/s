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
    attr_type[] attrs
}

struct closure_info {
    ir.node k
    ir.closure_expr clo
}

struct batch {
    location[] all_locs
    closure_info[] closures
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

func funcs(ir.func[] all_fns) {
    b := batch {
        all_locs: location[](),
        closures: closure_info[](),
        heap_loc: location {
            n: nil,
            curfn: nil,
            result_index: 0,
            captured: false,
            addrtaken: false,
            reassigned: false,
            attrs: attr_type[](),
        },
        mutator_loc: location {
            n: nil,
            curfn: nil,
            result_index: 0,
            captured: false,
            addrtaken: false,
            reassigned: false,
            attrs: attr_type[](),
        },
        callee_loc: location {
            n: nil,
            curfn: nil,
            result_index: 0,
            captured: false,
            addrtaken: false,
            reassigned: false,
            attrs: attr_type[](),
        },
        blank_loc: location {
            n: nil,
            curfn: nil,
            result_index: 0,
            captured: false,
            addrtaken: false,
            reassigned: false,
            attrs: attr_type[](),
        },
    }
    
    for function_decl in all_fns {
        batch_init_func(b, function_decl)
    }
    
    for function_decl in all_fns {
        batch_walk_func(b, function_decl)
    }
    
    for closure_item in b.closures {
            batch_flow_closure(b, closure_item.k, closure_item.clo)
    }
    
    batch_finish(b, all_fns)
}

func batch_init_func(batch b, ir.func function_decl) {
    return
}

func batch_walk_func(batch b, ir.func function_decl) {
    return
}

func batch_flow_closure(batch b, ir.node k, ir.closure_expr clo) {
    return
}

func batch_finish(batch b, ir.func[] fns) {
    return
}

func batch_param_tag(b* batch, ir.func function_decl, int narg, ir.param f) string {
    "~r0"
}

func escape_block(e* escape_analyzer, ir.node[] stmts) {
    for stmt in stmts {
        escape_stmt(e, stmt)
    }
}

func escape_stmt(e* escape_analyzer, ir.node n) {
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

func escape_expr(e* escape_analyzer, ir.node n) {
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

func new_location(b* batch, ir.node n, bool stack_only) option[location] {
    loc := location {
        n: n,
        curfn: nil,
        result_index: 0,
        captured: false,
        addrtaken: false,
        reassigned: false,
        attrs: attr_type[](),
    }
    
    b.all_locs.push(loc)
    option.some(loc)
}

func old_location(b* batch, ir.node n) location* {
    for i in 0..b.all_locs.len() {
        loc_n := b.all_locs[i].n
        if loc_n != nil && ir.nodes_equal(loc_n, n) {
            return &b.all_locs[i]
        }
    }
    &b.blank_loc
}

func location_has_attr(loc* location, attr_type a) bool {
    for attr_item in &loc.attrs {
        if attr_item == a {
            return true
        }
    }
    false
}

func location_add_attr(loc* location, attr_type a) {
    if !location_has_attr(loc, a) {
        loc.attrs.push(a)
    }
}
