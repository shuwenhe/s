#ifndef S_SEED_NATIVE_RECORD_NAMES_H
#define S_SEED_NATIVE_RECORD_NAMES_H
#include <ctype.h>
/* Resolve qualified type references while each source file still owns its
 * import scope. Never collect aliases from the merged compilation unit: two
 * files may use the same alias for different modules. Ordinary expression
 * member access and string values are deliberately untouched. */
static bool native_record_name(ast_node *file, char **name, source_pos pos, compile_error *err) {
    if (!name || !*name) return true;
    const char *text = *name;
    char out[IR_OPERAND_CAP];
    size_t used = 0, at = 0;
    while (text[at]) {
        size_t end = at;
        if (isalpha((unsigned char)text[at]) || text[at] == '_') {
            do { end++; } while (isalnum((unsigned char)text[end]) || text[end] == '_' || text[end] == '.');
        } else end++;
        const char *module = NULL;
        size_t alias_length = 0;
        for (size_t i = 0; i < file->as.program.statements.len; i++) {
            ast_node *n = file->as.program.statements.data[i];
            if (n->kind != AST_USE_DECL || !n->as.use_decl.alias || !n->as.use_decl.module_path) continue;
            size_t len = strlen(n->as.use_decl.alias);
            if (!len || end-at <= len || strncmp(text+at, n->as.use_decl.alias, len) || text[at+len] != '.') continue;
            if (module && strcmp(module, n->as.use_decl.module_path)) {
                error_set(err, ERR_SEMANTIC, pos.line, pos.column, "ambiguous native type import: %s", n->as.use_decl.alias);
                return false;
            }
            module = n->as.use_decl.module_path;
            alias_length = len;
        }
        size_t prefix = module ? strlen(module) : 0;
        size_t tail = end-at-alias_length;
        if (prefix + tail >= sizeof(out)-used) {
            error_set(err, ERR_SEMANTIC, pos.line, pos.column, "native qualified type name is too long"); return false;
        }
        if (module) { memcpy(out+used, module, prefix); used += prefix; }
        memcpy(out+used, text+at+alias_length, tail); used += tail;
        at = end;
    }
    out[used] = 0;
    if (!strcmp(out, text)) return true;
    char *resolved = malloc(used+1);
    if (!resolved) { error_set(err, ERR_OUT_OF_MEMORY, pos.line, pos.column, "native type name allocation failed"); return false; }
    memcpy(resolved, out, used+1);
    free(*name); *name = resolved;
    return true;
}
static bool native_record_type_spelling(ast_node *n, char *out, size_t cap) {
    if(n->kind==AST_IDENT_EXPR) return snprintf(out,cap,"%s",n->as.ident_expr.name)<(int)cap;
    if(n->kind!=AST_MEMBER_EXPR || !native_record_type_spelling(n->as.member_expr.object,out,cap)) return false;
    size_t len=strlen(out);
    return snprintf(out+len,cap-len,".%s",n->as.member_expr.member)<(int)(cap-len);
}
/* An empty index in a call callee is a type constructor, not value indexing.
 * Canonicalize its type expression without rewriting ordinary member access. */
static bool native_record_type_expression(ast_node *file, ast_node **place, compile_error *err) {
    ast_node *n=*place;
    if(n->kind==AST_INDEX_EXPR && !n->as.index_expr.index)
        return native_record_type_expression(file,&n->as.index_expr.object,err);
    if(n->kind==AST_IDENT_EXPR) return native_record_name(file,&n->as.ident_expr.name,n->pos,err);
    char spelling[IR_OPERAND_CAP];
    if(!native_record_type_spelling(n,spelling,sizeof(spelling))) return true; /* Semantic analysis diagnoses invalid constructors. */
    char *name=malloc(strlen(spelling)+1);
    if(!name) { error_set(err,ERR_OUT_OF_MEMORY,n->pos.line,n->pos.column,"native constructor type allocation failed"); return false; }
    strcpy(name,spelling);
    if(!native_record_name(file,&name,n->pos,err)) { free(name); return false; }
    ast_node *resolved=ast_new(AST_IDENT_EXPR,n->pos);
    if(!resolved) { free(name); error_set(err,ERR_OUT_OF_MEMORY,n->pos.line,n->pos.column,"native constructor type allocation failed"); return false; }
    resolved->as.ident_expr.name=name;
    ast_free(n); *place=resolved;
    return true;
}
static bool native_record_names_node(ast_node *, ast_node *, compile_error *);
static bool native_record_names_vec(ast_node *file, ast_vec *nodes, compile_error *err) {
    for (size_t i=0; i<nodes->len; i++) if (!native_record_names_node(file,nodes->data[i],err)) return false;
    return true;
}
static bool native_record_names_node(ast_node *file, ast_node *n, compile_error *err) {
    if (!n) return true;
#define NAME(value) do { if (!native_record_name(file, &(value), n->pos, err)) return false; } while (0)
#define NODE(value) do { if (!native_record_names_node(file, (value), err)) return false; } while (0)
#define VEC(value) do { if (!native_record_names_vec(file, &(value), err)) return false; } while (0)
    switch (n->kind) {
    case AST_PROGRAM: VEC(n->as.program.statements); break;
    case AST_BLOCK: VEC(n->as.block.statements); break;
    case AST_FN_STMT:
        NAME(n->as.fn_stmt.receiver_type); NAME(n->as.fn_stmt.return_type);
        for(size_t i=0;i<n->as.fn_stmt.param_count;i++) NAME(n->as.fn_stmt.param_types[i]);
        NODE(n->as.fn_stmt.body); break;
    case AST_EXTERN_DECL:
        NAME(n->as.extern_decl.return_type);
        for(size_t i=0;i<n->as.extern_decl.param_count;i++) NAME(n->as.extern_decl.param_types[i]);
        break;
    case AST_LET_STMT:
        if (n->as.let_stmt.type_name && !strcmp(n->as.let_stmt.type_name,"struct")) {
            ast_node *schema=n->as.let_stmt.value;
            if (schema && schema->kind==AST_STRUCT_EXPR) {
                for(size_t i=0;i<schema->as.struct_expr.field_values.len;i++) {
                    ast_node *field=schema->as.struct_expr.field_values.data[i];
                    if(field->kind==AST_STRING_EXPR) NAME(field->as.string_expr.literal);
                }
            }
            break;
        }
        NAME(n->as.let_stmt.type_name); NODE(n->as.let_stmt.value); break;
    case AST_CONST_DECL: case AST_VAR_DECL:
        NAME(n->as.var_decl.type_name); NODE(n->as.var_decl.value); break;
    case AST_RETURN_STMT:
        NODE(n->as.return_stmt.value);
        for(size_t i=0;i<n->as.return_stmt.values.len;i++)
            if(n->as.return_stmt.values.data[i]!=n->as.return_stmt.value) NODE(n->as.return_stmt.values.data[i]);
        break;
    case AST_EXPR_STMT: NODE(n->as.expr_stmt.expr); break;
    case AST_ASSIGN_STMT: NODE(n->as.assign_stmt.value); break;
    case AST_IF_STMT:
        NODE(n->as.if_stmt.condition); NODE(n->as.if_stmt.then_branch); NODE(n->as.if_stmt.else_branch); NODE(n->as.if_stmt.pattern_subject); break;
    case AST_WHILE_STMT: NODE(n->as.while_stmt.condition); NODE(n->as.while_stmt.body); break;
    case AST_FOR_STMT:
        NODE(n->as.for_stmt.init); NODE(n->as.for_stmt.condition); NODE(n->as.for_stmt.post); NODE(n->as.for_stmt.iterable); NODE(n->as.for_stmt.body); break;
    case AST_BINARY_EXPR: NODE(n->as.binary_expr.left); NODE(n->as.binary_expr.right); break;
    case AST_UNARY_EXPR: NODE(n->as.unary_expr.operand); break;
    case AST_ASSIGN_EXPR:
        NODE(n->as.assign_expr.target_object); NODE(n->as.assign_expr.target_index); NODE(n->as.assign_expr.target_expr); NODE(n->as.assign_expr.value); break;
    case AST_STRUCT_EXPR: NAME(n->as.struct_expr.type_name); VEC(n->as.struct_expr.field_values); break;
    case AST_STRING_EXPR:
        if(n->as.string_expr.is_type_name) NAME(n->as.string_expr.literal);
        break;
    case AST_ARRAY_EXPR: VEC(n->as.array_expr.items); break;
    case AST_MEMBER_EXPR: NODE(n->as.member_expr.object); break;
    case AST_INDEX_EXPR: NODE(n->as.index_expr.object); NODE(n->as.index_expr.index); break;
    case AST_SLICE_EXPR: NODE(n->as.slice_expr.object); NODE(n->as.slice_expr.start); NODE(n->as.slice_expr.end); break;
    case AST_CALL_EXPR:
        if(n->as.call_expr.callee && n->as.call_expr.callee->kind==AST_INDEX_EXPR && !n->as.call_expr.callee->as.index_expr.index)
            if(!native_record_type_expression(file,&n->as.call_expr.callee,err)) return false;
        NODE(n->as.call_expr.callee); VEC(n->as.call_expr.args); break;
    case AST_SROUTINE_STMT: NODE(n->as.sroutine_stmt.call); break;
    default: break;
    }
#undef NAME
#undef NODE
#undef VEC
    return true;
}
#endif
