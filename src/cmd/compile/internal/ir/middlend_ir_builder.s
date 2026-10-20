package compile.internal.ir

import (
    "compile.internal.parser"
)

struct ir_builder_context {
    ir_module module
    ir_function current_function
    ir_basicblock current_block

    ir_symbol_table symbol_table
    type_system type_system

    int block_counter
    int value_counter

    string[] errors
}

struct ir_symbol_table {
    ir_ir_symbol[] symbols
    ir_scope[] scopes
}

struct ir_ir_symbol {
    string name
    ir_value ir_value
    int block_id
}

struct ir_scope {
    int symbol_count
    int depth
}

struct type_system {
    string_ir_type_map type_cache
}

func ir_builder_context_new() ir_builder_context {
    ir_builder_context {
        module: ir_module_new(), block_counter 0, value_counter 0
    }
}

func ir_builder_build(ast* parser.ast_node) (ir_module, string[]) {
    ctx := ir_builder_context_new()

    ir_builder_visit_node(&ctx, ast)

    return ctx.module, ctx.errors
}

func ir_builder_visit_node(ir_builder_context* ctx, node* parser.ast_node) {
    if node == nil {
        return
    }

    switch node.node_type {
        case parser.ast_program:
            ir_builder_visit_program(ctx, node)
        case parser.ast_func:
            ir_builder_visit_func_decl(ctx, node)
        case parser.ast_package:
            ir_builder_visit_package(ctx, node)
        case parser.ast_struct:
            ir_builder_visit_struct_decl(ctx, node)
        case parser.ast_var:
            ir_builder_visit_var_decl(ctx, node)
    }
}

func ir_builder_visit_program(ir_builder_context* ctx, node* parser.ast_node) {

    if node.children != nil {
        for i := 0; i < node.children.len(); i = i + 1 {
            child := node.children[i]
            ir_builder_visit_node(ctx, child)
        }
    }
}

func ir_builder_visit_package(ir_builder_context* ctx, node* parser.ast_node) {

}

func ir_builder_visit_func_decl(ir_builder_context* ctx, node* parser.ast_node) {

    func_name := node.name
    return_type := "int"

    ir_func := ir_function_new(func_name, return_type)
    ctx.current_function = ir_func

    entry_block := ir_basicblock_new(ctx.block_counter, "entry")
    ctx.block_counter = ctx.block_counter + 1
    ctx.current_block = entry_block

    if node.children != nil && node.children.len() > 0 {
        params_node := node.children[0]
        ir_builder_visit_parameters(ctx, params_node)
    }

    if node.children != nil && node.children.len() > 1 {
        body_node := node.children[1]
        ir_builder_visit_block(ctx, body_node)
    }

    ir_func.basic_blocks = append(ir_func.basic_blocks, entry_block)

    ctx.module.functions = append(ctx.module.functions, ir_func)
}

func ir_builder_visit_parameters(ir_builder_context* ctx, params_node* parser.ast_node) {

    if params_node.children == nil {
        return
    }

    for i := 0; i < params_node.children.len(); i = i + 1 {
        param_node := params_node.children[i]
        param_name := param_node.name
        param_type := "int"

        param_value := ir_make_param_value(i, param_type)
        param_value.var_name = param_name
        param_value.value_id = ctx.value_counter
        ctx.value_counter = ctx.value_counter + 1

        ctx.current_function.parameters = append(ctx.current_function.parameters, param_value)
    }
}

func ir_builder_visit_block(ir_builder_context* ctx, block_node* parser.ast_node) {

    if block_node.children == nil {
        return
    }

    for i := 0; i < block_node.children.len(); i = i + 1 {
        stmt_node := block_node.children[i]
        ir_builder_visit_statement(ctx, stmt_node)
    }
}

func ir_builder_visit_statement(ir_builder_context* ctx, stmt_node* parser.ast_node) {
    if stmt_node == nil {
        return
    }

    switch stmt_node.node_type {
        case parser.ast_return:
            ir_builder_visit_return_stmt(ctx, stmt_node)
        case parser.ast_var:
            ir_builder_visit_var_decl(ctx, stmt_node)
        case parser.ast_if:
            ir_builder_visit_if_stmt(ctx, stmt_node)
        case parser.ast_for:
            ir_builder_visit_for_stmt(ctx, stmt_node)
        case parser.ast_while:
            ir_builder_visit_while_stmt(ctx, stmt_node)
        case parser.ast_expr_stmt:
            ir_builder_visit_expr_stmt(ctx, stmt_node)
    }
}

func ir_builder_visit_return_stmt(ir_builder_context* ctx, return_node* parser.ast_node) {

    value := ir_make_const_value("0", "int")

    if return_node.children != nil && return_node.children.len() > 0 {
        expr_node := return_node.children[0]
        value = ir_builder_visit_expression(ctx, expr_node)
    }

    ret_instr := ir_make_instr_return(value)
    ctx.current_block.set_terminator(ret_instr)
}

func ir_builder_visit_if_stmt(ir_builder_context* ctx, if_node* parser.ast_node) {

    cond_value := ir_make_const_value("1", "bool")
    if if_node.children != nil && if_node.children.len() > 0 {
        cond_node := if_node.children[0]
        cond_value = ir_builder_visit_expression(ctx, cond_node)
    }

    true_block_id := ctx.block_counter
    ctx.block_counter = ctx.block_counter + 1
    false_block_id := ctx.block_counter
    ctx.block_counter = ctx.block_counter + 1

    condbr := ir_make_instr_condbr(cond_value, true_block_id, false_block_id)
    ctx.current_block.set_terminator(condbr)

    true_block := ir_basicblock_new(true_block_id, "if.then")

    false_block := ir_basicblock_new(false_block_id, "if.else")
}

func ir_builder_visit_for_stmt(ir_builder_context* ctx, for_node* parser.ast_node) {

}

func ir_builder_visit_while_stmt(ir_builder_context* ctx, while_node* parser.ast_node) {

}

func ir_builder_visit_expr_stmt(ir_builder_context* ctx, expr_node* parser.ast_node) {
    ir_builder_visit_expression(ctx, expr_node)
}

func ir_builder_visit_var_decl(ir_builder_context* ctx, var_node* parser.ast_node) {

    var_name := var_node.name
    var_type := "int"

    alloca := ir_make_instr_alloca()
    alloca.result.var_name = var_name
    alloca.result.kindinfo = var_type

    ctx.current_block.add_instr(alloca)
}

func ir_builder_visit_expression(ir_builder_context* ctx, expr_node* parser.ast_node) ir_value {
    if expr_node == nil {
        return ir_make_const_value("0", "int")
    }

    switch expr_node.node_type {
        case parser.ast_int_lit:
            return ir_builder_visit_int_lit(ctx, expr_node)
        case parser.ast_binary_op:
            return ir_builder_visit_binary_op(ctx, expr_node)
        case parser.ast_ident:
            return ir_builder_visit_ident(ctx, expr_node)
        case parser.ast_call:
            return ir_builder_visit_call(ctx, expr_node)
        default:
            return ir_make_const_value("0", "int")
    }
}

func ir_builder_visit_int_lit(ir_builder_context* ctx, int_node* parser.ast_node) ir_value {
    ir_make_const_value(int_node.string_data, "int")
}

func ir_builder_visit_binary_op(ir_builder_context* ctx, binop_node* parser.ast_node) ir_value {
    if binop_node.children == nil || binop_node.children.len() < 2 {
        return ir_make_const_value("0", "int")
    }

    left := ir_builder_visit_expression(ctx, binop_node.children[0])
    right := ir_builder_visit_expression(ctx, binop_node.children[1])

    op := binop_node.int_data
    instr := ir_make_instr_binop(op, left, right, "int")

    ctx.current_block.add_instr(instr)
    instr.result
}

func ir_builder_visit_ident(ir_builder_context* ctx, ident_node* parser.ast_node) ir_value {
    ir_make_var_value(ident_node.name, "int")
}

func ir_builder_visit_call(ir_builder_context* ctx, call_node* parser.ast_node) ir_value {
    func_name := call_node.name
    args := ir_value[]()

    if call_node.children != nil {
        for i := 0; i < call_node.children.len(); i = i + 1 {
            arg := ir_builder_visit_expression(ctx, call_node.children[i])
            args = append(args, arg)
        }
    }

    instr := ir_make_instr_call(func_name, args, "int")
    ctx.current_block.add_instr(instr)
    instr.result
}

func ir_make_instr_alloca() ir_instruction {
    ir_instruction {
        instr_type: ir_instr_alloca
    }
}
