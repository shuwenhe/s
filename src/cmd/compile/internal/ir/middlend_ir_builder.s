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
}

func ir_builder_context_new() ir_builder_context {
    ir_builder_context {
        module: ir_module_new(), block_counter 0, value_counter 0
    }
}

struct ir_build_result {
    ir_module module
    string[] errors
}

// No AST references are retained in the result or context.
func ir_builder_build(ast* compile.internal.parser.ast_node) ir_build_result {
    ctx := ir_builder_context_new()

    ir_builder_visit_node(ctx*, ast)

    return ir_build_result { module: ctx.module, errors: ctx.errors }
}

func ir_builder_visit_node(ir_builder_context* ctx, node* compile.internal.parser.ast_node) {
    if node.node_type == 0 {
        return
    }

    switch node.node_type {
        case compile.internal.parser.ast_program:
            ir_builder_visit_program(ctx, node)
        case compile.internal.parser.ast_func_decl:
            ir_builder_visit_func_decl(ctx, node)
        case compile.internal.parser.ast_package:
            ir_builder_visit_package(ctx, node)
        case compile.internal.parser.ast_struct_decl:
            ir_builder_visit_struct_decl(ctx, node)
        case compile.internal.parser.ast_var_decl:
            ir_builder_visit_var_decl(ctx, node)
    }
}

func ir_builder_visit_program(ir_builder_context* ctx, node* compile.internal.parser.ast_node) {

    if len(node.children) > 0 {
        i := 0
        for i < len(node.children) {
            child := node.children[i]
            ir_builder_visit_node(ctx, child*)
            i = i + 1
        }
    }
}

func ir_builder_visit_package(ir_builder_context* ctx, node* compile.internal.parser.ast_node) {

}

func ir_builder_visit_func_decl(ir_builder_context* ctx, node* compile.internal.parser.ast_node) {

    func_name := node.name
    return_type := node.type_name
    if return_type == "" { return_type = "int" }

    ir_func := ir_function_new(func_name, return_type)
    ctx.current_function = ir_func

    entry_block := ir_basicblock_new(ctx.block_counter, "entry")
    ctx.block_counter = ctx.block_counter + 1
    ctx.current_block = entry_block

    if len(node.children) > 0 {
        params_node := node.children[0]
        ir_builder_visit_parameters(ctx, params_node*)
    }

    if len(node.children) > 1 {
        // The parser may insert a return-type group between params and body.
        body_index := len(node.children) - 1
        body_node := node.children[body_index]
        ir_builder_visit_block(ctx, body_node*)
    }

    ctx.current_function.basic_blocks = append(ctx.current_function.basic_blocks, ctx.current_block)

    ctx.module.functions = append(ctx.module.functions, ctx.current_function)
}

func ir_builder_visit_parameters(ir_builder_context* ctx, params_node* compile.internal.parser.ast_node) {

    if len(params_node.children) == 0 {
        return
    }

    i := 0
    for i < len(params_node.children) {
        param_node := params_node.children[i]
        param_name := param_node.name
        param_type := param_node.type_name
        if param_type == "" { param_type = "int" }

        param_value := ir_make_param_value(i, param_type)
        param_value.var_name = param_name
        param_value.value_id = ctx.value_counter
        ctx.value_counter = ctx.value_counter + 1

        ctx.current_function.parameters = append(ctx.current_function.parameters, param_value)
        i = i + 1
    }
}

func ir_builder_visit_block(ir_builder_context* ctx, block_node* compile.internal.parser.ast_node) {

    if len(block_node.children) == 0 {
        return
    }

    i := 0
    for i < len(block_node.children) {
        stmt_node := block_node.children[i]
        ir_builder_visit_statement(ctx, stmt_node*)
        i = i + 1
    }
}

func ir_builder_visit_statement(ir_builder_context* ctx, stmt_node* compile.internal.parser.ast_node) {
    if stmt_node.node_type == 0 {
        return
    }

    switch stmt_node.node_type {
        case compile.internal.parser.ast_return_stmt:
            ir_builder_visit_return_stmt(ctx, stmt_node)
        case compile.internal.parser.ast_var_decl:
            ir_builder_visit_var_decl(ctx, stmt_node)
        case compile.internal.parser.ast_if_stmt:
            ir_builder_visit_if_stmt(ctx, stmt_node)
        case compile.internal.parser.ast_for_stmt:
            ir_builder_visit_for_stmt(ctx, stmt_node)
        case compile.internal.parser.ast_while_stmt:
            ir_builder_visit_while_stmt(ctx, stmt_node)
        case compile.internal.parser.ast_expr_stmt:
            ir_builder_visit_expr_stmt(ctx, stmt_node)
    }
}

func ir_builder_visit_return_stmt(ir_builder_context* ctx, return_node* compile.internal.parser.ast_node) {

    value := ir_make_const_value("0", "int")

    if len(return_node.children) > 0 {
        expr_node := return_node.children[0]
        value = ir_builder_visit_expression(ctx, expr_node*)
    }

    ret_instr := ir_make_instr_return(value)
    ctx.current_block.terminator = ret_instr
}

func ir_builder_visit_if_stmt(ir_builder_context* ctx, if_node* compile.internal.parser.ast_node) {

    ctx.errors = append(ctx.errors, "if statement lowering is not implemented")
}

func ir_builder_visit_for_stmt(ir_builder_context* ctx, for_node* compile.internal.parser.ast_node) {
    ctx.errors = append(ctx.errors, "for statement lowering is not implemented")
}

func ir_builder_visit_while_stmt(ir_builder_context* ctx, while_node* compile.internal.parser.ast_node) {
    ctx.errors = append(ctx.errors, "while statement lowering is not implemented")
}

func ir_builder_visit_expr_stmt(ir_builder_context* ctx, expr_node* compile.internal.parser.ast_node) {
    ir_builder_visit_expression(ctx, expr_node)
}

func ir_builder_visit_var_decl(ir_builder_context* ctx, var_node* compile.internal.parser.ast_node) {

    var_name := var_node.name
    var_type := "int"

    alloca := ir_make_instr_alloca()
    alloca.result.var_name = var_name
    alloca.result.type_info = var_type

        ctx.current_block.instructions = append(ctx.current_block.instructions, alloca)
}

func ir_builder_visit_expression(ir_builder_context* ctx, expr_node* compile.internal.parser.ast_node) ir_value {
    switch expr_node.node_type {
        case compile.internal.parser.ast_int_lit:
            return ir_builder_visit_int_lit(ctx, expr_node)
        case compile.internal.parser.ast_ident:
            return ir_builder_visit_ident(ctx, expr_node)
        case compile.internal.parser.ast_binary_op:
            return ir_builder_visit_binary_op(ctx, expr_node)
        case compile.internal.parser.ast_call_expr:
            return ir_builder_visit_call(ctx, expr_node)
    }
    ctx.errors = append(ctx.errors, "unsupported AST expression")
    return ir_make_const_value("0", "int")
}

func ir_builder_visit_int_lit(ir_builder_context* ctx, int_node* compile.internal.parser.ast_node) ir_value {
    return ir_make_const_value(int_node.string_data, "int")
}

func ir_builder_visit_binary_op(ir_builder_context* ctx, binop_node* compile.internal.parser.ast_node) ir_value {
    if len(binop_node.children) < 2 {
        return ir_make_const_value("0", "int")
    }

    left_node := binop_node.children[0]
    left := ir_builder_visit_expression(ctx, left_node*)
    right_node := binop_node.children[1]
    right := ir_builder_visit_expression(ctx, right_node*)

    op := binop_node.int_data
    instr := ir_make_instr_binop(op, left, right, "int")

    ctx.current_block.instructions = append(ctx.current_block.instructions, instr)
    return instr.result
}

func ir_builder_visit_ident(ir_builder_context* ctx, ident_node* compile.internal.parser.ast_node) ir_value {
    return ir_make_var_value(ident_node.name, "int")
}

func ir_builder_visit_call(ir_builder_context* ctx, call_node* compile.internal.parser.ast_node) ir_value {
    func_name := call_node.name
    args := ir_value[]()

    if len(call_node.children) > 0 {
        i := 0
        for i < len(call_node.children) {
            arg_node := call_node.children[i]
            arg := ir_builder_visit_expression(ctx, arg_node*)
            args = append(args, arg)
            i = i + 1
        }
    }

    instr := ir_make_instr_call(func_name, args, "int")
    ctx.current_block.instructions = append(ctx.current_block.instructions, instr)
    instr.result
}

func ir_make_instr_alloca() ir_instruction {
    ir_instruction {
        instr_type: ir_instr_alloca
    }
}

func ir_builder_visit_struct_decl(ir_builder_context* ctx, node* compile.internal.parser.ast_node) {
    ctx.errors = append(ctx.errors, "struct declaration lowering is not implemented")
}
