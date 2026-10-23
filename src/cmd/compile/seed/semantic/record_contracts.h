#ifndef S_SEED_RECORD_CONTRACTS_H
#define S_SEED_RECORD_CONTRACTS_H
/* Native-only static gate. Legacy hosted compilation keeps its own contract. */
typedef struct record_contracts {
    ast_node *unit;
    const char *package_name;
    ast_node *path[65];
    bool array_edge[65];
} record_contracts;
static bool record_contract_visit(record_contracts *, ast_node *, compile_error *);
static bool record_contract_type_impl(record_contracts *c, const char *type, source_pos pos, unsigned depth, bool from_array, compile_error *err) {
    size_t i, f;
    if (!type || !*type || !strcmp(type, "()")) return true;
    if (strchr(type, '*') || strchr(type, '&') || !strcmp(type, "box") ||
        !strncmp(type, "own ", 4) || !strncmp(type, "ref ", 4) || !strncmp(type, "mutref ", 7)) {
        error_set(err, ERR_SEMANTIC, pos.line, pos.column,
            "native record transfer unsupported_owner or unproven borrow: %s", type); return false;
    }
    if (depth > 64) { error_set(err, ERR_SEMANTIC, pos.line, pos.column, "recursive by-value record contract"); return false; }
    if (strlen(type) >= 2 && !strcmp(type + strlen(type)-2, "[]")) {
        char base[IR_OPERAND_CAP];
        if (strlen(type) >= sizeof(base)) return false;
        strcpy(base, type); base[strlen(base)-2] = 0;
        return record_contract_type_impl(c, base, pos, depth, true, err);
    }
    const char *pkg = "";
    for (i = 0; i < c->unit->as.program.statements.len; i++) {
        ast_node *decl = c->unit->as.program.statements.data[i];
        if (decl->kind == AST_PACKAGE_DECL) pkg = decl->as.package_decl.name;
        if (decl->kind != AST_LET_STMT || !decl->as.let_stmt.type_name || strcmp(decl->as.let_stmt.type_name, "struct")) continue;
        char full[IR_OPERAND_CAP];
        if (snprintf(full, sizeof(full), "%s%s%s", pkg, *pkg ? "." : "", decl->as.let_stmt.name) >= (int)sizeof(full)) return false;
        if (strcmp(full, type) && (strcmp(pkg, c->package_name) || strcmp(decl->as.let_stmt.name, type))) continue;
        unsigned j, k;
        for (j = 0; j < depth; j++) if (c->path[j] == decl) {
            bool indirect = from_array;
            for (k = j+1; k < depth; k++) indirect = indirect || c->array_edge[k];
            if (indirect) return true;
            error_set(err, ERR_SEMANTIC, pos.line, pos.column, "recursive by-value record contract: %s", type); return false;
        }
        c->path[depth] = decl; c->array_edge[depth] = from_array;
        const char *saved_package = c->package_name;
        c->package_name = pkg;
        ast_node *schema = decl->as.let_stmt.value;
        for (f = 0; f < schema->as.struct_expr.field_count; f++) {
            if (!record_contract_type_impl(c, schema->as.struct_expr.field_values.data[f]->as.string_expr.literal, pos, depth+1, false, err)) { c->package_name = saved_package; return false; }
        }
        c->package_name = saved_package;
        return true;
    }
    return true;
}
static bool record_contract_type(record_contracts *c, const char *type, source_pos pos, unsigned depth, compile_error *err) {
    (void)depth;
    return record_contract_type_impl(c, type, pos, 0, false, err);
}
static bool record_contract_vec(record_contracts *c, ast_vec *v, compile_error *err) {
    size_t i;
    for (i = 0; i < v->len; i++) if (!record_contract_visit(c, v->data[i], err)) return false;
    return true;
}
static bool record_contract_visit(record_contracts *c, ast_node *n, compile_error *err) {
    size_t i;
    if (!n) return true;
    switch (n->kind) {
    case AST_PACKAGE_DECL: c->package_name = n->as.package_decl.name; return true;
    case AST_PROGRAM: return record_contract_vec(c, &n->as.program.statements, err);
    case AST_BLOCK: return record_contract_vec(c, &n->as.block.statements, err);
    case AST_LET_STMT:
        if (n->as.let_stmt.type_name && !strcmp(n->as.let_stmt.type_name, "struct")) return true;
        return record_contract_type(c, n->as.let_stmt.type_name, n->pos, 0, err) && record_contract_visit(c, n->as.let_stmt.value, err);
    case AST_STRUCT_EXPR:
        return record_contract_type(c, n->as.struct_expr.type_name, n->pos, 0, err) && record_contract_vec(c, &n->as.struct_expr.field_values, err);
    case AST_STRING_EXPR:
        return !n->as.string_expr.is_type_name || record_contract_type(c, n->as.string_expr.literal, n->pos, 0, err);
    case AST_FN_STMT:
        if(n->native_template) return true; /* Concrete instantiations are checked below. */
        /* The receiver is already parameter zero and follows its proved
         * transfer contract; do not reject that same borrow a second time. */
        if (!(n->as.fn_stmt.native_borrow_mask&1ULL) && !record_contract_type(c, n->as.fn_stmt.receiver_type, n->pos, 0, err)) return false;
        if (!record_contract_type(c, n->as.fn_stmt.return_type, n->pos, 0, err)) return false;
        for (i = 0; i < n->as.fn_stmt.param_count; i++) {
            const char *type=n->as.fn_stmt.param_types[i]; char base[IR_OPERAND_CAP];
            if(i<64 && (n->as.fn_stmt.native_borrow_mask&(1ULL<<i)) && borrow_type(type,base)) type=base;
            if(!record_contract_type(c,type,n->pos,0,err)) return false;
        }
        return record_contract_visit(c, n->as.fn_stmt.body, err);
    case AST_IF_STMT: return record_contract_visit(c, n->as.if_stmt.condition, err) && record_contract_visit(c, n->as.if_stmt.then_branch, err) && record_contract_visit(c, n->as.if_stmt.else_branch, err);
    case AST_WHILE_STMT: return record_contract_visit(c, n->as.while_stmt.condition, err) && record_contract_visit(c, n->as.while_stmt.body, err);
    case AST_FOR_STMT: return record_contract_visit(c, n->as.for_stmt.init, err) && record_contract_visit(c, n->as.for_stmt.condition, err) && record_contract_visit(c, n->as.for_stmt.post, err) && record_contract_visit(c, n->as.for_stmt.iterable, err) && record_contract_visit(c, n->as.for_stmt.body, err);
    case AST_RETURN_STMT: return record_contract_visit(c, n->as.return_stmt.value, err) && record_contract_vec(c, &n->as.return_stmt.values, err);
    case AST_ASSIGN_STMT: return record_contract_visit(c, n->as.assign_stmt.value, err);
    case AST_ASSIGN_EXPR: return record_contract_visit(c, n->as.assign_expr.target_expr, err) && record_contract_visit(c, n->as.assign_expr.value, err);
    case AST_BINARY_EXPR: return record_contract_visit(c, n->as.binary_expr.left, err) && record_contract_visit(c, n->as.binary_expr.right, err);
    case AST_UNARY_EXPR: return record_contract_visit(c, n->as.unary_expr.operand, err);
    case AST_MEMBER_EXPR: return record_contract_visit(c, n->as.member_expr.object, err);
    case AST_CALL_EXPR:
        return record_contract_type(c, n->as.call_expr.resolved_array_type, n->pos, 0, err) &&
            record_contract_visit(c, n->as.call_expr.callee, err) && record_contract_vec(c, &n->as.call_expr.args, err);
    case AST_ARRAY_EXPR: return record_contract_vec(c, &n->as.array_expr.items, err);
    case AST_INDEX_EXPR: return record_contract_visit(c, n->as.index_expr.object, err) && record_contract_visit(c, n->as.index_expr.index, err);
    case AST_SLICE_EXPR: return record_contract_visit(c, n->as.slice_expr.object, err) && record_contract_visit(c, n->as.slice_expr.start, err) && record_contract_visit(c, n->as.slice_expr.end, err);
    case AST_EXPR_STMT: return record_contract_visit(c, n->as.expr_stmt.expr, err);
    case AST_SROUTINE_STMT: error_set(err, ERR_SEMANTIC, n->pos.line, n->pos.column, "native record allocator does not support concurrent execution"); return false;
    default: return true;
    }
}
static bool record_validate_transfer_contracts(ast_node *unit, record_contracts *out, compile_error *err) {
    out->unit = unit; out->package_name = "";
    return unit && unit->kind == AST_PROGRAM && record_contract_visit(out, unit, err);
}
#endif
