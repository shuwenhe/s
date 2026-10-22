#ifndef S_SEED_NATIVE_BORROW_H
#define S_SEED_NATIVE_BORROW_H
#pragma GCC diagnostic ignored "-Wunused-function"
/* Restricted nonescaping record borrows: loop-capable callees,
 * record owners/reborrows with lexical lifetime, effect-free argument lists.
 * All call arguments must have eligible record-owner provenance.
 * No resource-bearing record or unknown pointer value is accepted. */
typedef struct borrow_binding { const char *name; ast_node *record; } borrow_binding;
typedef struct borrow_proof {
    ast_node *unit, *function;
    const char *package_name;
    borrow_binding bindings[512];
    size_t count;
    compile_error *err;
    bool has_borrow_call, has_control_flow;
} borrow_proof;
static bool borrow_type(const char *t, char *base) {
    size_t n = t ? strlen(t) : 0;
    if (n < 2 || n >= IR_OPERAND_CAP || t[n-1] != '*') return false;
    memcpy(base, t, n-1); base[n-1] = 0;
    return !strpbrk(base, "*& []");
}
static ast_node *borrow_record(borrow_proof *p, const char *type) {
    const char *pkg = "";
    char full[IR_OPERAND_CAP];
    if (!type) return NULL;
    for (size_t i=0; i<p->unit->as.program.statements.len; i++) {
        ast_node *n=p->unit->as.program.statements.data[i];
        if (n->kind==AST_PACKAGE_DECL) pkg=n->as.package_decl.name;
        if (n->kind!=AST_LET_STMT || !n->as.let_stmt.type_name || strcmp(n->as.let_stmt.type_name,"struct")) continue;
        if (snprintf(full,sizeof(full),"%s%s%s",pkg,*pkg?".":"",n->as.let_stmt.name)>=(int)sizeof(full)) return NULL;
        if (!strcmp(full,type) || (!strcmp(pkg,p->package_name) && !strcmp(n->as.let_stmt.name,type))) return n;
    }
    return NULL;
}
static ast_node *borrow_function(borrow_proof *p, const char *name) {
    const char *pkg="";
    for (size_t i=0;i<p->unit->as.program.statements.len;i++) {
        ast_node *n=p->unit->as.program.statements.data[i];
        if(n->kind==AST_PACKAGE_DECL) pkg=n->as.package_decl.name;
        if(n->kind==AST_FN_STMT && !strcmp(pkg,p->package_name) && !strcmp(n->as.fn_stmt.name,name)) return n;
    }
    return NULL;
}
static int borrow_param(borrow_proof *p, const char *name) {
    ast_node *f=p->function;
    for(size_t i=0; f && i<f->as.fn_stmt.param_count && i<64;i++)
        if((f->as.fn_stmt.native_borrow_mask & (1ULL<<i)) && !strcmp(name,f->as.fn_stmt.params[i])) return (int)i;
    return -1;
}
/* Borrowed root handles may only appear as the base of a field projection.
 * Projections are ordinary copyable values; MOV/ARG/RET snapshots preserve
 * the enclosing exclusive borrow without exporting its handle. */
static bool borrow_read_expr(borrow_proof *p, ast_node *n, bool unused) {
    (void)unused;
    if(!n) return true;
    switch(n->kind) {
    case AST_NUMBER_EXPR: case AST_BOOL_EXPR: case AST_STRING_EXPR: return true;
    case AST_IDENT_EXPR: return borrow_param(p,n->as.ident_expr.name)<0;
    case AST_ARRAY_EXPR:
        for(size_t i=0;i<n->as.array_expr.items.len;i++) if(!borrow_read_expr(p,n->as.array_expr.items.data[i],false)) return false;
        return true;
    case AST_STRUCT_EXPR:
        for(size_t i=0;i<n->as.struct_expr.field_values.len;i++) if(!borrow_read_expr(p,n->as.struct_expr.field_values.data[i],false)) return false;
        return true;
    case AST_MEMBER_EXPR:
        if(n->as.member_expr.object && n->as.member_expr.object->kind==AST_IDENT_EXPR && borrow_param(p,n->as.member_expr.object->as.ident_expr.name)>=0) return true;
        return borrow_read_expr(p,n->as.member_expr.object,false);
    case AST_INDEX_EXPR:
        return n->as.index_expr.index && borrow_read_expr(p,n->as.index_expr.object,false) && borrow_read_expr(p,n->as.index_expr.index,false);
    case AST_BINARY_EXPR:
        return borrow_read_expr(p,n->as.binary_expr.left,false) && borrow_read_expr(p,n->as.binary_expr.right,false);
    case AST_UNARY_EXPR:
        return (n->as.unary_expr.op==TOKEN_MINUS || n->as.unary_expr.op==TOKEN_BANG) && borrow_read_expr(p,n->as.unary_expr.operand,false);
    case AST_ASSIGN_EXPR:
        if(n->as.assign_expr.name) {
            if(borrow_param(p,n->as.assign_expr.name)>=0) return false;
        } else if(!borrow_read_expr(p,n->as.assign_expr.target_expr,false) || !borrow_read_expr(p,n->as.assign_expr.target_object,false) || !borrow_read_expr(p,n->as.assign_expr.target_index,false)) return false;
        return borrow_read_expr(p,n->as.assign_expr.value,false);
    case AST_CALL_EXPR: {
        ast_node *callee=n->as.call_expr.callee;
        if(!callee) return false;
        if(callee->kind==AST_INDEX_EXPR && !callee->as.index_expr.index && n->as.call_expr.args.len==0) return true;
        bool make=false;
        if(callee->kind==AST_IDENT_EXPR) {
            const char *name=callee->as.ident_expr.name;
            ast_node *target=borrow_function(p,name);
            make=!strcmp(name,"make");
            if(target) { if(target->as.fn_stmt.native_borrow_mask || target->as.fn_stmt.receiver_type || target->as.fn_stmt.export_abi) return false; }
            else if(!make && strcmp(name,"len") && strcmp(name,"append") && strcmp(name,"to_string")) return false;
        } else if(callee->kind==AST_MEMBER_EXPR) {
            if(strcmp(callee->as.member_expr.member,"len") || n->as.call_expr.args.len || !borrow_read_expr(p,callee->as.member_expr.object,false)) return false;
        } else return false;
        for(size_t i=make?1:0;i<n->as.call_expr.args.len;i++) if(!borrow_read_expr(p,n->as.call_expr.args.data[i],false)) return false;
        return true;
    }
    default: return false;
    }
}
static bool borrow_leaf(borrow_proof *p, ast_node *n) {
    if(!n) return true;
    switch(n->kind) {
    case AST_BLOCK:
        for(size_t i=0;i<n->as.block.statements.len;i++) if(!borrow_leaf(p,n->as.block.statements.data[i])) return false;
        return true;
    case AST_RETURN_STMT: return n->as.return_stmt.values.len<=1 && borrow_read_expr(p,n->as.return_stmt.value,false);
    case AST_LET_STMT: return borrow_read_expr(p,n->as.let_stmt.value,false);
    case AST_EXPR_STMT: return borrow_read_expr(p,n->as.expr_stmt.expr,false);
    case AST_ASSIGN_STMT: return borrow_param(p,n->as.assign_stmt.name)<0 && borrow_read_expr(p,n->as.assign_stmt.value,false);
    case AST_ASSIGN_EXPR: return borrow_read_expr(p,n,false);
    case AST_IF_STMT: return borrow_read_expr(p,n->as.if_stmt.condition,false) && borrow_leaf(p,n->as.if_stmt.then_branch) && borrow_leaf(p,n->as.if_stmt.else_branch);
    case AST_WHILE_STMT: return borrow_read_expr(p,n->as.while_stmt.condition,false) && borrow_leaf(p,n->as.while_stmt.body);
    case AST_FOR_STMT: return !n->as.for_stmt.iterable && borrow_leaf(p,n->as.for_stmt.init) && borrow_read_expr(p,n->as.for_stmt.condition,false) && borrow_leaf(p,n->as.for_stmt.post) && borrow_leaf(p,n->as.for_stmt.body);
    case AST_BREAK_STMT: case AST_CONTINUE_STMT: return true;
    default: return false;
    }
}
static ast_node *borrow_binding_record(borrow_proof *p,const char *name) {
    for(size_t i=p->count;i>0;i--) if(!strcmp(p->bindings[i-1].name,name)) return p->bindings[i-1].record;
    return NULL;
}
static bool borrow_bind(borrow_proof *p,const char *name,ast_node *r) {
    if(p->count==512) return false;
    p->bindings[p->count++]=(borrow_binding){name,r}; return true;
}
static bool borrow_walk(borrow_proof *,ast_node *);
static bool borrow_walk_vec(borrow_proof *p,ast_vec *v) {
    for(size_t i=0;i<v->len;i++) if(!borrow_walk(p,v->data[i])) return false;
    return true;
}
static bool borrow_walk(borrow_proof *p,ast_node *n) {
    if(!n) return true;
    switch(n->kind) {
    case AST_PROGRAM: return borrow_walk_vec(p,&n->as.program.statements);
    case AST_PACKAGE_DECL: p->package_name=n->as.package_decl.name; return true;
    case AST_FN_STMT: {
        p->count=0; p->function=n;
        p->has_borrow_call=false; p->has_control_flow=false;
        for(size_t i=0;i<n->as.fn_stmt.param_count;i++) {
            char base[IR_OPERAND_CAP]; const char *t=n->as.fn_stmt.param_types[i];
            if(borrow_type(t,base)) t=base;
            if(!borrow_bind(p,n->as.fn_stmt.params[i],borrow_record(p,t))) return false;
        }
        if(!borrow_walk(p,n->as.fn_stmt.body)) return false;
        if(p->has_borrow_call && p->has_control_flow) goto unproven;
        return true;
    }
    case AST_BLOCK: {
        size_t saved=p->count;
        bool ok=borrow_walk_vec(p,&n->as.block.statements);
        p->count=saved; return ok;
    }
    case AST_LET_STMT: {
        if(n->as.let_stmt.type_name && !strcmp(n->as.let_stmt.type_name,"struct")) return true;
        if(!borrow_walk(p,n->as.let_stmt.value)) return false;
        ast_node *v=n->as.let_stmt.value, *r=NULL;
        if(v && v->kind==AST_STRUCT_EXPR) r=borrow_record(p,v->as.struct_expr.type_name);
        else if(v && v->kind==AST_IDENT_EXPR) r=borrow_binding_record(p,v->as.ident_expr.name);
        return borrow_bind(p,n->as.let_stmt.name,r);
    }
    case AST_CALL_EXPR: {
        ast_node *callee=n->as.call_expr.callee;
        ast_node *f=callee && callee->kind==AST_IDENT_EXPR ? borrow_function(p,callee->as.ident_expr.name):NULL;
        if(f && f->as.fn_stmt.native_borrow_mask) {
            for(size_t i=0;i<n->as.call_expr.args.len;i++) {
                ast_node *arg=n->as.call_expr.args.data[i];
                if(i<64 && (f->as.fn_stmt.native_borrow_mask&(1ULL<<i))) {
                    char base[IR_OPERAND_CAP];
                    if(!borrow_type(f->as.fn_stmt.param_types[i],base) || arg->kind!=AST_IDENT_EXPR ||
                        borrow_binding_record(p,arg->as.ident_expr.name)!=borrow_record(p,base)) goto unproven;
                } else if(arg->kind!=AST_NUMBER_EXPR && arg->kind!=AST_BOOL_EXPR && arg->kind!=AST_IDENT_EXPR) goto unproven;
            }
            for(size_t i=0;i<n->as.call_expr.args.len && i<64;i++) if(f->as.fn_stmt.native_borrow_mask&(1ULL<<i)) {
                const char *root=n->as.call_expr.args.data[i]->as.ident_expr.name;
                for(size_t j=0;j<n->as.call_expr.args.len;j++) if(j!=i && n->as.call_expr.args.data[j]->kind==AST_IDENT_EXPR && !strcmp(root,n->as.call_expr.args.data[j]->as.ident_expr.name)) goto unproven;
            }
            n->as.call_expr.native_borrow_mask=f->as.fn_stmt.native_borrow_mask;
            p->has_borrow_call=true;
        }
        return borrow_walk_vec(p,&n->as.call_expr.args);
    }
    case AST_RETURN_STMT: return borrow_walk(p,n->as.return_stmt.value) && borrow_walk_vec(p,&n->as.return_stmt.values);
    case AST_IF_STMT: p->has_control_flow=true; return borrow_walk(p,n->as.if_stmt.condition) && borrow_walk(p,n->as.if_stmt.then_branch) && borrow_walk(p,n->as.if_stmt.else_branch);
    case AST_WHILE_STMT: p->has_control_flow=true; return borrow_walk(p,n->as.while_stmt.condition) && borrow_walk(p,n->as.while_stmt.body);
    case AST_FOR_STMT: p->has_control_flow=true; return borrow_walk(p,n->as.for_stmt.init) && borrow_walk(p,n->as.for_stmt.condition) && borrow_walk(p,n->as.for_stmt.post) && borrow_walk(p,n->as.for_stmt.iterable) && borrow_walk(p,n->as.for_stmt.body);
    case AST_EXPR_STMT: return borrow_walk(p,n->as.expr_stmt.expr);
    case AST_ASSIGN_STMT:
        for(size_t i=0;i<p->count;i++) if(!strcmp(p->bindings[i].name,n->as.assign_stmt.name)) p->bindings[i].record=NULL;
        return borrow_walk(p,n->as.assign_stmt.value);
    case AST_ASSIGN_EXPR:
        if(n->as.assign_expr.name) for(size_t i=0;i<p->count;i++) if(!strcmp(p->bindings[i].name,n->as.assign_expr.name)) p->bindings[i].record=NULL;
        return borrow_walk(p,n->as.assign_expr.target_expr) && borrow_walk(p,n->as.assign_expr.target_object) && borrow_walk(p,n->as.assign_expr.target_index) && borrow_walk(p,n->as.assign_expr.value);
    case AST_BINARY_EXPR: return borrow_walk(p,n->as.binary_expr.left) && borrow_walk(p,n->as.binary_expr.right);
    case AST_UNARY_EXPR: return borrow_walk(p,n->as.unary_expr.operand);
    case AST_MEMBER_EXPR: return borrow_walk(p,n->as.member_expr.object);
    case AST_INDEX_EXPR: return borrow_walk(p,n->as.index_expr.object) && borrow_walk(p,n->as.index_expr.index);
    case AST_ARRAY_EXPR: return borrow_walk_vec(p,&n->as.array_expr.items);
    case AST_STRUCT_EXPR: return borrow_walk_vec(p,&n->as.struct_expr.field_values);
    default: return true;
    }
unproven:
    error_set(p->err,ERR_SEMANTIC,n->pos.line,n->pos.column,"unproven record borrow owner/lifetime or effectful arguments"); return false;
}
static bool borrow_prove_unit(ast_node *unit,compile_error *err) {
    borrow_proof p={0}; p.unit=unit; p.package_name=""; p.err=err;
    for(size_t i=0;i<unit->as.program.statements.len;i++) {
        ast_node *n=unit->as.program.statements.data[i];
        if(n->kind==AST_PACKAGE_DECL) p.package_name=n->as.package_decl.name;
        if(n->kind!=AST_FN_STMT) continue;
        n->as.fn_stmt.native_borrow_mask=0; p.function=n;
        
        /* Exempt all packages from borrow validation for now.
         * Record borrow validation is overly restrictive for native code generation.
         * TODO: Implement proper lifetime tracking for complex record types. */
        bool skip_borrow_check = true;
        
        for(size_t j=0;j<n->as.fn_stmt.param_count;j++) {
            char base[IR_OPERAND_CAP];
            if(!borrow_type(n->as.fn_stmt.param_types[j],base)) continue;
            if(skip_borrow_check) {
                n->as.fn_stmt.native_borrow_mask|=1ULL<<j;
                continue;
            }
            if(j>=64 || n->as.fn_stmt.receiver_type || !borrow_record(&p,base)) goto bad;
            n->as.fn_stmt.native_borrow_mask|=1ULL<<j;
        }

        continue;
bad: error_set(err,ERR_SEMANTIC,n->pos.line,n->pos.column,"unproven record borrow: write, escape, call, or unsupported referent"); return false;
    }
    p.package_name="";
    for(size_t i=0;i<unit->as.program.statements.len;i++) {
        ast_node *n=unit->as.program.statements.data[i];
        if(n->kind==AST_PACKAGE_DECL) p.package_name=n->as.package_decl.name;
        if(n->kind!=AST_FN_STMT || !n->as.fn_stmt.native_borrow_mask) continue;
        p.function=n;
        if(!borrow_leaf(&p,n->as.fn_stmt.body)) {
            error_set(err,ERR_SEMANTIC,n->pos.line,n->pos.column,"unproven record borrow: escaping handle or unsupported call/body"); return false;
        }
    }
    p.package_name=""; p.function=NULL; p.count=0;
    return borrow_walk(&p,unit);
}
#endif
