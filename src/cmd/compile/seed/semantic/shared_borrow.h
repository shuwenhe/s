#ifndef S_SEED_SHARED_BORROW_H
#define S_SEED_SHARED_BORROW_H
/* Deliberately small proof system: leaf read-only functions, scalar returns,
 * record owners/reborrows with lexical lifetime, effect-free argument lists.
 * Raw T* remains unknown; no owning pointer is reclassified as a borrow. */
typedef struct shared_binding { const char *name; ast_node *record; } shared_binding;
typedef struct shared_proof {
    ast_node *unit, *function;
    const char *package_name;
    shared_binding bindings[512];
    size_t count;
    compile_error *err;
} shared_proof;
static bool shared_scalar(const char *t) {
    return t && (!strcmp(t,"int") || !strcmp(t,"bool") || !strcmp(t,"byte") || !strcmp(t,"()"));
}
static bool shared_type(const char *t, char *base) {
    size_t n = t ? strlen(t) : 0;
    if (n < 2 || n >= IR_OPERAND_CAP || t[n-1] != '&') return false;
    memcpy(base, t, n-1); base[n-1] = 0;
    return !strpbrk(base, "*& []");
}
static ast_node *shared_record(shared_proof *p, const char *type) {
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
static ast_node *shared_function(shared_proof *p, const char *name) {
    const char *pkg="";
    for (size_t i=0;i<p->unit->as.program.statements.len;i++) {
        ast_node *n=p->unit->as.program.statements.data[i];
        if(n->kind==AST_PACKAGE_DECL) pkg=n->as.package_decl.name;
        if(n->kind==AST_FN_STMT && !strcmp(pkg,p->package_name) && !strcmp(n->as.fn_stmt.name,name)) return n;
    }
    return NULL;
}
static int shared_param(shared_proof *p, const char *name) {
    ast_node *f=p->function;
    for(size_t i=0; f && i<f->as.fn_stmt.param_count && i<64;i++)
        if((f->as.fn_stmt.native_shared_mask & (1ULL<<i)) && !strcmp(name,f->as.fn_stmt.params[i])) return (int)i;
    return -1;
}
static bool shared_read_expr(shared_proof *p, ast_node *n, bool identity) {
    if(!n) return true;
    switch(n->kind) {
    case AST_NUMBER_EXPR: case AST_BOOL_EXPR: return true;
    case AST_IDENT_EXPR:
        if(shared_param(p,n->as.ident_expr.name)>=0) return identity;
        for(size_t i=0;i<p->function->as.fn_stmt.param_count;i++)
            if(!strcmp(p->function->as.fn_stmt.params[i],n->as.ident_expr.name)) return shared_scalar(p->function->as.fn_stmt.param_types[i]);
        return false;
    case AST_MEMBER_EXPR: {
        ast_node *root=n->as.member_expr.object;
        if(!root || root->kind!=AST_IDENT_EXPR) return false;
        int i=shared_param(p,root->as.ident_expr.name);
        char base[IR_OPERAND_CAP];
        if(i<0 || !shared_type(p->function->as.fn_stmt.param_types[i],base)) return false;
        ast_node *r=shared_record(p,base);
        if(!r) return false;
        ast_node *schema=r->as.let_stmt.value;
        for(size_t j=0;j<schema->as.struct_expr.field_count;j++)
            if(!strcmp(schema->as.struct_expr.field_names[j],n->as.member_expr.member))
                return shared_scalar(schema->as.struct_expr.field_values.data[j]->as.string_expr.literal);
        return false;
    }
    case AST_BINARY_EXPR: {
        bool eq=n->as.binary_expr.op==TOKEN_EQ || n->as.binary_expr.op==TOKEN_NE;
        return shared_read_expr(p,n->as.binary_expr.left,eq) && shared_read_expr(p,n->as.binary_expr.right,eq);
    }
    case AST_UNARY_EXPR:
        return (n->as.unary_expr.op==TOKEN_MINUS || n->as.unary_expr.op==TOKEN_BANG) && shared_read_expr(p,n->as.unary_expr.operand,false);
    default: return false;
    }
}
static bool shared_leaf(shared_proof *p, ast_node *n) {
    if(!n) return true;
    if(n->kind==AST_BLOCK) {
        for(size_t i=0;i<n->as.block.statements.len;i++) if(!shared_leaf(p,n->as.block.statements.data[i])) return false;
        return true;
    }
    if(n->kind==AST_RETURN_STMT)
        return n->as.return_stmt.values.len==0 && shared_read_expr(p,n->as.return_stmt.value,false);
    if(n->kind==AST_IF_STMT)
        return shared_read_expr(p,n->as.if_stmt.condition,false) && shared_leaf(p,n->as.if_stmt.then_branch) && shared_leaf(p,n->as.if_stmt.else_branch);
    return false;
}
static ast_node *shared_binding_record(shared_proof *p,const char *name) {
    for(size_t i=p->count;i>0;i--) if(!strcmp(p->bindings[i-1].name,name)) return p->bindings[i-1].record;
    return NULL;
}
static bool shared_bind(shared_proof *p,const char *name,ast_node *r) {
    if(p->count==512) return false;
    p->bindings[p->count++]=(shared_binding){name,r}; return true;
}
static bool shared_walk(shared_proof *,ast_node *);
static bool shared_walk_vec(shared_proof *p,ast_vec *v) {
    for(size_t i=0;i<v->len;i++) if(!shared_walk(p,v->data[i])) return false;
    return true;
}
static bool shared_walk(shared_proof *p,ast_node *n) {
    if(!n) return true;
    switch(n->kind) {
    case AST_PROGRAM: return shared_walk_vec(p,&n->as.program.statements);
    case AST_PACKAGE_DECL: p->package_name=n->as.package_decl.name; return true;
    case AST_FN_STMT: {
        p->count=0; p->function=n;
        for(size_t i=0;i<n->as.fn_stmt.param_count;i++) {
            char base[IR_OPERAND_CAP]; const char *t=n->as.fn_stmt.param_types[i];
            if(shared_type(t,base)) t=base;
            if(!shared_bind(p,n->as.fn_stmt.params[i],shared_record(p,t))) return false;
        }
        return shared_walk(p,n->as.fn_stmt.body);
    }
    case AST_BLOCK: {
        size_t saved=p->count;
        bool ok=shared_walk_vec(p,&n->as.block.statements);
        p->count=saved; return ok;
    }
    case AST_LET_STMT: {
        if(n->as.let_stmt.type_name && !strcmp(n->as.let_stmt.type_name,"struct")) return true;
        if(!shared_walk(p,n->as.let_stmt.value)) return false;
        ast_node *v=n->as.let_stmt.value, *r=NULL;
        if(v && v->kind==AST_STRUCT_EXPR) r=shared_record(p,v->as.struct_expr.type_name);
        else if(v && v->kind==AST_IDENT_EXPR) r=shared_binding_record(p,v->as.ident_expr.name);
        return shared_bind(p,n->as.let_stmt.name,r);
    }
    case AST_CALL_EXPR: {
        ast_node *callee=n->as.call_expr.callee;
        ast_node *f=callee && callee->kind==AST_IDENT_EXPR ? shared_function(p,callee->as.ident_expr.name):NULL;
        if(f && f->as.fn_stmt.native_shared_mask) {
            for(size_t i=0;i<n->as.call_expr.args.len;i++) {
                ast_node *arg=n->as.call_expr.args.data[i];
                if(i<64 && (f->as.fn_stmt.native_shared_mask&(1ULL<<i))) {
                    char base[IR_OPERAND_CAP];
                    if(!shared_type(f->as.fn_stmt.param_types[i],base) || arg->kind!=AST_IDENT_EXPR ||
                        shared_binding_record(p,arg->as.ident_expr.name)!=shared_record(p,base)) goto unproven;
                } else if(arg->kind!=AST_NUMBER_EXPR && arg->kind!=AST_BOOL_EXPR && arg->kind!=AST_IDENT_EXPR) goto unproven;
            }
            n->as.call_expr.native_shared_mask=f->as.fn_stmt.native_shared_mask;
        }
        return shared_walk_vec(p,&n->as.call_expr.args);
    }
    case AST_RETURN_STMT: return shared_walk(p,n->as.return_stmt.value) && shared_walk_vec(p,&n->as.return_stmt.values);
    case AST_IF_STMT: return shared_walk(p,n->as.if_stmt.condition) && shared_walk(p,n->as.if_stmt.then_branch) && shared_walk(p,n->as.if_stmt.else_branch);
    case AST_WHILE_STMT: return shared_walk(p,n->as.while_stmt.condition) && shared_walk(p,n->as.while_stmt.body);
    case AST_FOR_STMT: return shared_walk(p,n->as.for_stmt.init) && shared_walk(p,n->as.for_stmt.condition) && shared_walk(p,n->as.for_stmt.post) && shared_walk(p,n->as.for_stmt.iterable) && shared_walk(p,n->as.for_stmt.body);
    case AST_EXPR_STMT: return shared_walk(p,n->as.expr_stmt.expr);
    case AST_ASSIGN_STMT:
        for(size_t i=0;i<p->count;i++) if(!strcmp(p->bindings[i].name,n->as.assign_stmt.name)) p->bindings[i].record=NULL;
        return shared_walk(p,n->as.assign_stmt.value);
    case AST_ASSIGN_EXPR:
        if(n->as.assign_expr.name) for(size_t i=0;i<p->count;i++) if(!strcmp(p->bindings[i].name,n->as.assign_expr.name)) p->bindings[i].record=NULL;
        return shared_walk(p,n->as.assign_expr.target_expr) && shared_walk(p,n->as.assign_expr.target_object) && shared_walk(p,n->as.assign_expr.target_index) && shared_walk(p,n->as.assign_expr.value);
    case AST_BINARY_EXPR: return shared_walk(p,n->as.binary_expr.left) && shared_walk(p,n->as.binary_expr.right);
    case AST_UNARY_EXPR: return shared_walk(p,n->as.unary_expr.operand);
    case AST_MEMBER_EXPR: return shared_walk(p,n->as.member_expr.object);
    case AST_INDEX_EXPR: return shared_walk(p,n->as.index_expr.object) && shared_walk(p,n->as.index_expr.index);
    case AST_ARRAY_EXPR: return shared_walk_vec(p,&n->as.array_expr.items);
    case AST_STRUCT_EXPR: return shared_walk_vec(p,&n->as.struct_expr.field_values);
    default: return true;
    }
unproven:
    error_set(p->err,ERR_SEMANTIC,n->pos.line,n->pos.column,"unproven shared borrow owner/lifetime or effectful arguments"); return false;
}
static bool shared_prove_unit(ast_node *unit,compile_error *err) {
    shared_proof p={0}; p.unit=unit; p.package_name=""; p.err=err;
    for(size_t i=0;i<unit->as.program.statements.len;i++) {
        ast_node *n=unit->as.program.statements.data[i];
        if(n->kind==AST_PACKAGE_DECL) p.package_name=n->as.package_decl.name;
        if(n->kind!=AST_FN_STMT) continue;
        n->as.fn_stmt.native_shared_mask=0; p.function=n;
        for(size_t j=0;j<n->as.fn_stmt.param_count;j++) {
            char base[IR_OPERAND_CAP];
            if(!shared_type(n->as.fn_stmt.param_types[j],base)) continue;
            if(j>=64 || n->as.fn_stmt.receiver_type || !shared_record(&p,base)) goto bad;
            n->as.fn_stmt.native_shared_mask|=1ULL<<j;
        }
        if(n->as.fn_stmt.native_shared_mask && (!shared_scalar(n->as.fn_stmt.return_type) || !shared_leaf(&p,n->as.fn_stmt.body))) goto bad;
        continue;
bad: error_set(err,ERR_SEMANTIC,n->pos.line,n->pos.column,"unproven shared borrow: write, escape, call, or unsupported referent"); return false;
    }
    p.package_name=""; p.function=NULL; p.count=0;
    return shared_walk(&p,unit);
}
#endif
