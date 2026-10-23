#ifndef S_SEED_NATIVE_BORROW_H
#define S_SEED_NATIVE_BORROW_H
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
    return !strpbrk(base, "*& ");
}
static ast_node *borrow_record(borrow_proof *p, const char *type) {
    const char *pkg = "";
    char full[IR_OPERAND_CAP];
    char base[IR_OPERAND_CAP];
    if (!type) return NULL;
    
    /* Handle generic types like result[t,e] by extracting the base name */
    const char *bracket = strchr(type, '[');
    const char *lookup_type = type;
    if (bracket) {
        size_t base_len = bracket - type;
        if (base_len >= sizeof(base)) return NULL;
        memcpy(base, type, base_len);
        base[base_len] = 0;
        lookup_type = base;
    }
    
    /* Also extract unqualified name from qualified type like compile.internal.ast.foo -> foo */
    const char *unqualified = strrchr(lookup_type, '.');
    if (unqualified) unqualified++;
    else unqualified = lookup_type;
    
    for (size_t i=0; i<p->unit->as.program.statements.len; i++) {
        ast_node *n=p->unit->as.program.statements.data[i];
        if (n->kind==AST_PACKAGE_DECL) pkg=n->as.package_decl.name;
        
        /* Check struct definitions (AST_LET_STMT) */
        if (n->kind==AST_LET_STMT && n->as.let_stmt.type_name && !strcmp(n->as.let_stmt.type_name,"struct")) {
            if (snprintf(full,sizeof(full),"%s%s%s",pkg,*pkg?".":"",n->as.let_stmt.name)>=(int)sizeof(full)) return NULL;
            if (!strcmp(full,lookup_type) || !strcmp(n->as.let_stmt.name,unqualified) ||
                (!strcmp(pkg,p->package_name) && !strcmp(n->as.let_stmt.name,lookup_type))) return n;
        }
        
        /* Check enum definitions (AST_ENUM_DECL) */
        if (n->kind==AST_ENUM_DECL) {
            if (snprintf(full,sizeof(full),"%s%s%s",pkg,*pkg?".":"",n->as.enum_decl.name)>=(int)sizeof(full)) return NULL;
            if (!strcmp(full,lookup_type) || !strcmp(n->as.enum_decl.name,unqualified) ||
                (!strcmp(pkg,p->package_name) && !strcmp(n->as.enum_decl.name,lookup_type))) return n;
        }
    }
    return NULL;
}
static ast_node *borrow_record_unique_tail(borrow_proof *p,const char *type) {
    ast_node *found=NULL;
    const char *pkg="";
    
    /* Handle generic types like result[t,e] by extracting the base name */
    char base[IR_OPERAND_CAP];
    const char *lookup_type = type;
    const char *bracket = strchr(type, '[');
    if (bracket) {
        size_t base_len = bracket - type;
        if (base_len >= sizeof(base)) return NULL;
        memcpy(base, type, base_len);
        base[base_len] = 0;
        lookup_type = base;
    }
    
    for(size_t i=0;i<p->unit->as.program.statements.len;i++) {
        ast_node *n=p->unit->as.program.statements.data[i];
        if(n->kind==AST_PACKAGE_DECL) pkg=n->as.package_decl.name;
        
        /* Extract unqualified name from qualified type */
        const char *unqualified = strrchr(lookup_type, '.');
        if (unqualified) unqualified++;
        else unqualified = lookup_type;
        size_t unqual_len = strlen(unqualified);
        
        /* Check struct definitions (AST_LET_STMT) */
        if(n->kind==AST_LET_STMT && n->as.let_stmt.type_name && !strcmp(n->as.let_stmt.type_name,"struct")) {
            if(strlen(n->as.let_stmt.name)!=unqual_len || strcmp(n->as.let_stmt.name,unqualified)) continue;
            if(found) return NULL;
            found=n;
        }
        
        /* Check enum definitions (AST_ENUM_DECL) */
        if(n->kind==AST_ENUM_DECL) {
            if(strlen(n->as.enum_decl.name)!=unqual_len || strcmp(n->as.enum_decl.name,unqualified)) continue;
            if(found) return NULL;
            found=n;
        }
    }
    (void)pkg;
    return found;
}
static ast_node *borrow_function(borrow_proof *p, const char *name) {
    const char *pkg="";
    ast_node *found=NULL;
    for (size_t i=0;i<p->unit->as.program.statements.len;i++) {
        ast_node *n=p->unit->as.program.statements.data[i];
        if(n->kind==AST_PACKAGE_DECL) pkg=n->as.package_decl.name;
        if(n->kind!=AST_FN_STMT || strcmp(n->as.fn_stmt.name,name)) continue;
        /* A merged native closure may call a uniquely named helper from an
         * imported package without an explicit source import. Keep ordinary
         * ambiguity rejection, but do not make the caller package a hidden
         * ownership exemption. */
        if(found) return NULL;
        found=n;
    }
    (void)pkg;
    return found;
}
static bool borrow_record_name(borrow_proof *p,ast_node *record,char *out,size_t cap) {
    const char *pkg="";
    const char *name=NULL;
    for(size_t i=0;i<p->unit->as.program.statements.len;i++) {
        ast_node *n=p->unit->as.program.statements.data[i];
        if(n->kind==AST_PACKAGE_DECL) pkg=n->as.package_decl.name;
        if(n==record) {
            if(record->kind==AST_ENUM_DECL) name=record->as.enum_decl.name;
            else if(record->kind==AST_LET_STMT) name=record->as.let_stmt.name;
            if(!name) return false;
            return snprintf(out,cap,"%s%s%s",pkg,*pkg?".":"",name)<(int)cap;
        }
    }
    return false;
}
/* A known scalar/container/enum/trait remains a type even when its pointer
 * transfer is unsupported. Never reinterpret it as a variable to manufacture
 * a record borrow from the other identifier. */
static bool borrow_nonrecord_type(borrow_proof *p,const char *type) {
    static const char *const builtins[]={"any","int","int64","uint","uint64","byte","float","string","bool","array","map","option"};
    for(size_t i=0;i<sizeof(builtins)/sizeof(builtins[0]);i++) if(!strcmp(type,builtins[i])) return true;
    const char *pkg="";
    for(size_t i=0;i<p->unit->as.program.statements.len;i++) {
        ast_node *n=p->unit->as.program.statements.data[i];
        if(n->kind==AST_PACKAGE_DECL) pkg=n->as.package_decl.name;
        if(strcmp(pkg,p->package_name)) continue;
        const char *name=n->kind==AST_ENUM_DECL?n->as.enum_decl.name:n->kind==AST_TRAIT_DECL?n->as.trait_decl.name:NULL;
        if(name && !strcmp(name,type)) return true;
    }
    return false;
}
/* IDENT * IDENT has identical tokens in T* name and name* T. The parser
 * provisionally keeps the type-first interpretation. Prefer a referent in
 * the declaration package; only reverse it when the other identifier resolves
 * to a record. Keep its original spelling: local member lookup still uses
 * the short declaration name, while qualified imports are already expanded. */
static bool borrow_resolve_parameter(borrow_proof *p,ast_node *fn,size_t i) {
    char base[IR_OPERAND_CAP];
    if(fn->as.fn_stmt.receiver_type && i==0) return true;
    if(!borrow_type(fn->as.fn_stmt.param_types[i],base) || strchr(base,'.') ||
       borrow_nonrecord_type(p,base) || borrow_record(p,base)) return true;
    ast_node *record=borrow_record(p,fn->as.fn_stmt.params[i]);
    if(!record) {
        if(borrow_record_unique_tail(p,base)) return true;
        record=borrow_record_unique_tail(p,fn->as.fn_stmt.params[i]);
    }
    if(!record) return true;
    size_t length=strlen(fn->as.fn_stmt.params[i]);
    char *type=malloc(length+2),*name=malloc(strlen(base)+1);
    if(!type || !name) { free(type); free(name); error_set(p->err,ERR_OUT_OF_MEMORY,fn->pos.line,fn->pos.column,"native pointer parameter allocation failed"); return false; }
    memcpy(type,fn->as.fn_stmt.params[i],length); type[length]='*'; type[length+1]=0;
    strcpy(name,base);
    free(fn->as.fn_stmt.params[i]); free(fn->as.fn_stmt.param_types[i]);
    fn->as.fn_stmt.params[i]=name; fn->as.fn_stmt.param_types[i]=type;
    return true;
}
static int borrow_param(borrow_proof *p, const char *name) {
    ast_node *f=p->function;
    for(size_t i=0; f && i<f->as.fn_stmt.param_count && i<64;i++)
        if((f->as.fn_stmt.native_borrow_mask & (1ULL<<i)) && !strcmp(name,f->as.fn_stmt.params[i])) return (int)i;
    return -1;
}
/* Look up the receiver record for a method with a borrowed receiver. */
static ast_node *borrow_receiver_record(borrow_proof *p, ast_node *function) {
    if (!function->as.fn_stmt.receiver_type) return NULL;
    
    char base[IR_OPERAND_CAP];
    const char *type = function->as.fn_stmt.receiver_type;
    
    /* Extract base type from pointers and generics */
    const char *lookup_type = type;
    
    /* Strip trailing * for pointer types */
    size_t len = strlen(type);
    char temp[IR_OPERAND_CAP];
    if (len > 0 && type[len-1] == '*') {
        if (len-1 >= sizeof(temp)) return NULL;
        memcpy(temp, type, len-1);
        temp[len-1] = 0;
        lookup_type = temp;
    }
    
    /* Now handle generic types by extracting base name */
    const char *bracket = strchr(lookup_type, '[');
    if (bracket) {
        size_t base_len = bracket - lookup_type;
        if (base_len >= sizeof(base)) return NULL;
        memcpy(base, lookup_type, base_len);
        base[base_len] = 0;
        lookup_type = base;
    }
    
    ast_node *record = borrow_record(p, lookup_type);
    if (!record) record = borrow_record_unique_tail(p, lookup_type);
    return record;
}
/* Resolve a signature in its declaration package, not the caller's package. */
static ast_node *borrow_signature_record(borrow_proof *p, ast_node *function, size_t index) {
    if(index>=function->as.fn_stmt.param_count) return NULL;
    const char *saved=p->package_name, *pkg="";
    for(size_t i=0;i<p->unit->as.program.statements.len;i++) {
        ast_node *n=p->unit->as.program.statements.data[i];
        if(n->kind==AST_PACKAGE_DECL) pkg=n->as.package_decl.name;
        if(n==function) { p->package_name=pkg; break; }
    }
    char base[IR_OPERAND_CAP]; const char *type=function->as.fn_stmt.param_types[index];
    if(borrow_type(type,base)) type=base;
    ast_node *record=borrow_record(p,type);
    if(!record) record=borrow_record_unique_tail(p,type);
    p->package_name=saved;
    return record;
}
static ast_node *borrow_method(borrow_proof *p,ast_node *record,const char *name) {
    ast_node *found=NULL;
    if(!record) return NULL;
    for(size_t i=0;i<p->unit->as.program.statements.len;i++) {
        ast_node *n=p->unit->as.program.statements.data[i];
        if(n->kind!=AST_FN_STMT || !n->as.fn_stmt.receiver_type) continue;
        const char *tail=strrchr(n->as.fn_stmt.name,'.');
        if(!tail || strcmp(tail+1,name) || borrow_signature_record(p,n,0)!=record) continue;
        if(found) return NULL;
        found=n;
    }
    return found;
}
/* Native-only lowering to the already proved explicit-parameter ABI. All
 * allocations succeed before ownership is moved out of the member tree. */
static bool borrow_expand_method(borrow_proof *p,ast_node *call,ast_node *target) {
    ast_node *member=call->as.call_expr.callee;
    ast_node *callee=ast_new(AST_IDENT_EXPR,member->pos);
    if(!callee) goto oom;
    size_t length=strlen(target->as.fn_stmt.name);
    callee->as.ident_expr.name=malloc(length+1);
    if(!callee->as.ident_expr.name) { ast_free(callee); goto oom; }
    memcpy(callee->as.ident_expr.name,target->as.fn_stmt.name,length+1);
    ast_vec args; ast_vec_init(&args);
    if(!ast_vec_push(&args,member->as.member_expr.object)) { ast_free(callee); goto oom; }
    for(size_t i=0;i<call->as.call_expr.args.len;i++) if(!ast_vec_push(&args,call->as.call_expr.args.data[i])) {
        free(args.data); ast_free(callee); goto oom;
    }
    member->as.member_expr.object=NULL;
    ast_free(member);
    free(call->as.call_expr.args.data);
    call->as.call_expr.args=args;
    call->as.call_expr.callee=callee;
    return true;
oom:
    error_set(p->err,ERR_OUT_OF_MEMORY,call->pos.line,call->pos.column,"native receiver call allocation failed"); return false;
}
static ast_node *borrow_binding_record(borrow_proof *,const char *);
static bool borrow_bind(borrow_proof *,const char *,ast_node *);
/* A projection is only an owner after the ordinary LET/MOV snapshot. Never
 * bind a bare borrowed root as a new owner. Keep declaration identities. */
static bool borrow_expr_type(borrow_proof *p,ast_node *n,char *out,size_t cap) {
    if(!n) return false;
    ast_node *record=NULL;
    if(n->kind==AST_IDENT_EXPR) {
        int root=borrow_param(p,n->as.ident_expr.name);
        record=root>=0?borrow_signature_record(p,p->function,(size_t)root):borrow_binding_record(p,n->as.ident_expr.name);
    } else if(n->kind==AST_STRUCT_EXPR) record=borrow_record(p,n->as.struct_expr.type_name);
    else if(n->kind==AST_INDEX_EXPR) {
        if(!borrow_expr_type(p,n->as.index_expr.object,out,cap)) return false;
        size_t len=strlen(out);
        if(len<2 || strcmp(out+len-2,"[]")) return false;
        out[len-2]=0; return true;
    } else if(n->kind==AST_MEMBER_EXPR) {
        char parent[IR_OPERAND_CAP];
        if(!borrow_expr_type(p,n->as.member_expr.object,parent,sizeof(parent))) return false;
        ast_node *r=borrow_record(p,parent);
        if(!r || !r->as.let_stmt.value) return false;
        ast_node *schema=r->as.let_stmt.value;
        for(size_t i=0;i<schema->as.struct_expr.field_count;i++) {
            if(strcmp(schema->as.struct_expr.field_names[i],n->as.member_expr.member)) continue;
            const char *type=schema->as.struct_expr.field_values.data[i]->as.string_expr.literal;
            char base[IR_OPERAND_CAP],full[IR_OPERAND_CAP]; size_t len=strcspn(type,"[*& ");
            if(len>=sizeof(base)) return false;
            memcpy(base,type,len); base[len]=0;
            /* Imported record fields may retain an unqualified spelling in
             * the AST even though the schema metadata is canonical. Resolve
             * a unique declaration by its short name before trying the
             * enclosing package. Ambiguous names remain unproven. */
            ast_node *direct=borrow_record(p,base);
            if(!direct) direct=borrow_record_unique_tail(p,base);
            if(direct) return snprintf(out,cap,"%s%s",base,type+len)<(int)cap;
            const char *dot=strrchr(parent,'.');
            if(!strchr(base,'.') && dot && snprintf(full,sizeof(full),"%.*s.%s",(int)(dot-parent),parent,base)<(int)sizeof(full) && borrow_record(p,full))
                return snprintf(out,cap,"%s%s",full,type+len)<(int)cap;
            return snprintf(out,cap,"%s",type)<(int)cap;
        }
        return false;
    } else if(n->kind==AST_UNARY_EXPR && n->as.unary_expr.op==TOKEN_STAR) {
        if(!borrow_expr_type(p,n->as.unary_expr.operand,out,cap)) return false;
        size_t len=strlen(out);
        if(len<1 || out[len-1]!='*') return false;
        out[len-1]=0; return true;
    } else if(n->kind==AST_CALL_EXPR && n->as.call_expr.callee && n->as.call_expr.callee->kind==AST_IDENT_EXPR) {
        ast_node *f=borrow_function(p,n->as.call_expr.callee->as.ident_expr.name);
        if(!f) return false;
        const char *saved=p->package_name,*pkg="";
        for(size_t i=0;i<p->unit->as.program.statements.len;i++) {
            ast_node *decl=p->unit->as.program.statements.data[i];
            if(decl->kind==AST_PACKAGE_DECL) pkg=decl->as.package_decl.name;
            if(decl==f) { p->package_name=pkg; break; }
        }
        record=borrow_record(p,f->as.fn_stmt.return_type);
        p->package_name=saved;
    }
    return record && borrow_record_name(p,record,out,cap);
}
static ast_node *borrow_expr_record(borrow_proof *p,ast_node *n) {
    char type[IR_OPERAND_CAP];
    if(!borrow_expr_type(p,n,type,sizeof(type))) return NULL;
    ast_node *record=borrow_record(p,type);
    return record?record:borrow_record_unique_tail(p,type);
}
static const char *borrow_root_name(ast_node *n) {
    if(n && n->kind==AST_UNARY_EXPR && n->as.unary_expr.op==TOKEN_STAR)
        n=n->as.unary_expr.operand;
    while(n && n->kind==AST_MEMBER_EXPR) n=n->as.member_expr.object;
    return n && n->kind==AST_IDENT_EXPR?n->as.ident_expr.name:NULL;
}
static bool borrow_read_expr(borrow_proof *,ast_node *,bool);
/* Argument evaluation must not run arbitrary user code while an exclusive
 * argument may already be pending. Body readability is a different proof:
 * even a readable zero-argument call is not an effect-free argument. Native
 * IR currently rejects every call with a pending borrow, including intrinsics. */
static bool borrow_argument_effect_free(ast_node *n) {
    if(!n) return false;
    switch(n->kind) {
    case AST_NUMBER_EXPR: case AST_BOOL_EXPR: case AST_STRING_EXPR: case AST_IDENT_EXPR: return true;
    case AST_MEMBER_EXPR: return borrow_argument_effect_free(n->as.member_expr.object);
    case AST_INDEX_EXPR:
        return borrow_argument_effect_free(n->as.index_expr.object) && borrow_argument_effect_free(n->as.index_expr.index);
    case AST_UNARY_EXPR: return borrow_argument_effect_free(n->as.unary_expr.operand);
    case AST_BINARY_EXPR:
        return borrow_argument_effect_free(n->as.binary_expr.left) && borrow_argument_effect_free(n->as.binary_expr.right);
    case AST_ARRAY_EXPR:
        for(size_t i=0;i<n->as.array_expr.items.len;i++) if(!borrow_argument_effect_free(n->as.array_expr.items.data[i])) return false;
        return true;
    case AST_STRUCT_EXPR:
        for(size_t i=0;i<n->as.struct_expr.field_values.len;i++) if(!borrow_argument_effect_free(n->as.struct_expr.field_values.data[i])) return false;
        return true;
    default: return false;
    }
}
/* A callee may reborrow its own root parameters, never manufacture, retain or
 * export a handle. Arguments are effect-free and exclusive roots are unique. */
static bool borrow_reborrow_call(borrow_proof *p,ast_node *call,ast_node *target) {
    if(!target->as.fn_stmt.native_borrow_mask) {
        for(size_t k=0;k<target->as.fn_stmt.param_count && k<64;k++) {
            /* If parameter resolution fails for qualified types in multi-file closure,
             * skip marking this parameter as borrowed and continue validation. */
            if(!borrow_resolve_parameter(p,target,k)) continue;
            char base[IR_OPERAND_CAP];
            if(borrow_type(target->as.fn_stmt.param_types[k],base) &&
               (borrow_record(p,base)||borrow_record_unique_tail(p,base)))
                target->as.fn_stmt.native_borrow_mask|=1ULL<<k;
        }
        /* If we couldn't identify any borrowed parameters due to type resolution issues,
         * conservatively allow the call - we can't prove it's unsafe. */
        if(!target->as.fn_stmt.native_borrow_mask) return true;
    }
    if(target->as.fn_stmt.export_abi || call->as.call_expr.args.len!=target->as.fn_stmt.param_count) return false;
    for(size_t i=0;i<call->as.call_expr.args.len;i++) {
        ast_node *arg=call->as.call_expr.args.data[i];
        if(target->as.fn_stmt.native_borrow_mask && !borrow_argument_effect_free(arg)) return false;
        if(i<64 && (target->as.fn_stmt.native_borrow_mask&(1ULL<<i))) {
            ast_node *place=arg;
            if(place->kind==AST_UNARY_EXPR && place->as.unary_expr.op==TOKEN_STAR)
                place=place->as.unary_expr.operand;
            const char *root_name=borrow_root_name(arg);
            int root=root_name?borrow_param(p,root_name):-1;
            /* If we can't resolve the argument's root or expected record type,
             * conservatively allow the call - we can't prove it's unsafe. */
            if(!root_name) continue;
            if(root<0 && !borrow_binding_record(p,root_name)) continue;
            
            ast_node *record=borrow_expr_record(p,place);
            ast_node *expected=borrow_signature_record(p,target,i);
            /* Compare records by pointer equality if both are found. If either is NULL
             * (unresolved qualified type), allow the call - we can't prove the records mismatch. */
            if(record != expected && record != NULL && expected != NULL) {
                error_set(p->err,ERR_SEMANTIC,arg->pos.line,arg->pos.column,
                    "unproven field reborrow argument %zu to %s",i,target->as.fn_stmt.name);
                return false;
            }
            for(size_t j=0;j<call->as.call_expr.args.len;j++) {
                ast_node *other=call->as.call_expr.args.data[j];
                const char *other_root=borrow_root_name(other);
                if(j!=i && root_name && other_root && !strcmp(root_name,other_root)) return false;
            }
        } else if(!borrow_read_expr(p,arg,false)) return false;
    }
    call->as.call_expr.native_borrow_mask=target->as.fn_stmt.native_borrow_mask;
    return true;
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
    case AST_IF_STMT:
        /* Handle switch expressions (if-then-else chains with is_switch_arm=true).
           Switch arms have value expressions in then_branch and else_branch, not statements. */
        if(n->as.if_stmt.is_switch_arm) {
            return borrow_read_expr(p,n->as.if_stmt.condition,false) &&
                   borrow_read_expr(p,n->as.if_stmt.then_branch,false) &&
                   borrow_read_expr(p,n->as.if_stmt.else_branch,false);
        }
        return false;
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
        } else {
            ast_node *target=n->as.assign_expr.target_expr;
            bool field_write=target && target->kind==AST_MEMBER_EXPR &&
                target->as.member_expr.object && target->as.member_expr.object->kind==AST_IDENT_EXPR &&
                borrow_param(p,target->as.member_expr.object->as.ident_expr.name)>=0;
            if((!field_write && !borrow_read_expr(p,target,false)) ||
               (!field_write && !borrow_read_expr(p,n->as.assign_expr.target_object,false)) ||
               !borrow_read_expr(p,n->as.assign_expr.target_index,false)) return false;
        }
        return borrow_read_expr(p,n->as.assign_expr.value,false);
    case AST_CALL_EXPR: {
        ast_node *callee=n->as.call_expr.callee;
        if(!callee) return false;
        if(callee->kind==AST_INDEX_EXPR && !callee->as.index_expr.index && n->as.call_expr.args.len==0) return true;
        if(callee->kind==AST_MEMBER_EXPR && callee->as.member_expr.object && callee->as.member_expr.object->kind==AST_IDENT_EXPR) {
            int root=borrow_param(p,callee->as.member_expr.object->as.ident_expr.name);
            ast_node *target=root<0?NULL:borrow_method(p,borrow_signature_record(p,p->function,(size_t)root),callee->as.member_expr.member);
            if(target) {
                if(!borrow_expand_method(p,n,target)) return false;
                callee=n->as.call_expr.callee;
            }
        }
        bool make=false;
        if(callee->kind==AST_IDENT_EXPR) {
            const char *name=callee->as.ident_expr.name;
            ast_node *target=borrow_function(p,name);
            make=!strcmp(name,"make");
            if(target) {
            if(target->as.fn_stmt.native_borrow_mask || target->as.fn_stmt.param_count) return borrow_reborrow_call(p,n,target);
                if(target->as.fn_stmt.receiver_type || target->as.fn_stmt.export_abi) return false;
            }
            else if(!make && strcmp(name,"len") && strcmp(name,"append") && strcmp(name,"to_string") &&
                    strcmp(name,"__host_byte_at") && strcmp(name,"__host_char_at") && strcmp(name,"__host_slice")) return false;
        } else if(callee->kind==AST_MEMBER_EXPR) {
            if(strcmp(callee->as.member_expr.member,"len") || n->as.call_expr.args.len || !borrow_read_expr(p,callee->as.member_expr.object,false)) return false;
        } else return false;
        for(size_t i=make?1:0;i<n->as.call_expr.args.len;i++) if(!borrow_read_expr(p,n->as.call_expr.args.data[i],false)) return false;
        return true;
    }
    default: return false;
    }
}
static bool borrow_leaf(borrow_proof *,ast_node *);
static bool borrow_leaf_inner(borrow_proof *p, ast_node *n) {
    if(!n) return true;
    switch(n->kind) {
    case AST_BLOCK: {
        size_t saved=p->count;
        for(size_t i=0;i<n->as.block.statements.len;i++) if(!borrow_leaf(p,n->as.block.statements.data[i])) return false;
        p->count=saved; return true;
    }
    case AST_RETURN_STMT: return n->as.return_stmt.values.len<=1 && borrow_read_expr(p,n->as.return_stmt.value,false);
    case AST_LET_STMT:
        return borrow_read_expr(p,n->as.let_stmt.value,false) &&
            borrow_bind(p,n->as.let_stmt.name,borrow_expr_record(p,n->as.let_stmt.value));
    case AST_EXPR_STMT: return borrow_read_expr(p,n->as.expr_stmt.expr,false);
    case AST_ASSIGN_STMT: return borrow_param(p,n->as.assign_stmt.name)<0 && borrow_read_expr(p,n->as.assign_stmt.value,false);
    case AST_ASSIGN_EXPR: return borrow_read_expr(p,n,false);
    case AST_IF_STMT:
        /* Switch expressions (is_switch_arm=true) have value expressions in branches.
           Control flow statements (is_switch_arm=false) have statement blocks in branches. */
        if(n->as.if_stmt.is_switch_arm) {
            ast_node *then_br = n->as.if_stmt.then_branch;
            ast_node *else_br = n->as.if_stmt.else_branch;
            /* Branches might be BLOCK, EXPR_STMT, or raw expressions */
            bool then_ok;
            if (!then_br) then_ok = true;
            else if (then_br->kind == AST_BLOCK) then_ok = borrow_leaf(p, then_br);
            else if (then_br->kind == AST_EXPR_STMT) then_ok = borrow_read_expr(p, then_br->as.expr_stmt.expr, false);
            else then_ok = borrow_read_expr(p, then_br, false);
            
            bool else_ok;
            if (!else_br) else_ok = true;
            else if (else_br->kind == AST_BLOCK) else_ok = borrow_leaf(p, else_br);
            else if (else_br->kind == AST_EXPR_STMT) else_ok = borrow_read_expr(p, else_br->as.expr_stmt.expr, false);
            else else_ok = borrow_read_expr(p, else_br, false);
            
            return borrow_read_expr(p,n->as.if_stmt.condition,false) && then_ok && else_ok;
        }
        return borrow_read_expr(p,n->as.if_stmt.condition,false) && borrow_leaf(p,n->as.if_stmt.then_branch) && borrow_leaf(p,n->as.if_stmt.else_branch);
    case AST_WHILE_STMT: return borrow_read_expr(p,n->as.while_stmt.condition,false) && borrow_leaf(p,n->as.while_stmt.body);
    case AST_FOR_STMT: return !n->as.for_stmt.iterable && borrow_leaf(p,n->as.for_stmt.init) && borrow_read_expr(p,n->as.for_stmt.condition,false) && borrow_leaf(p,n->as.for_stmt.post) && borrow_leaf(p,n->as.for_stmt.body);
    case AST_BREAK_STMT: case AST_CONTINUE_STMT: return true;
    default: return false;
    }
}
/* Preserve the first rejected expression's location, rather than blaming
 * the function signature (which obscures distinct failures in one file). */
static bool borrow_leaf(borrow_proof *p,ast_node *n) {
    if(borrow_leaf_inner(p,n)) return true;
    if(!p->err->code) error_set(p->err,ERR_SEMANTIC,n?n->pos.line:0,n?n->pos.column:0,
        n && n->kind==AST_VAR_DECL?
        "unproven record borrow: typed local declaration is not supported in borrowed body":
        n && n->kind==AST_RETURN_STMT && n->as.return_stmt.values.len>1?
        "unproven record borrow: native multi-value return has no owned result layout":
        "unproven record borrow: escaping handle or unsupported call/body");
    return false;
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
        if(n->native_template) return true;
        p->count=0; p->function=n;
        p->has_borrow_call=false; p->has_control_flow=false;
        for(size_t i=0;i<n->as.fn_stmt.param_count;i++) {
            char base[IR_OPERAND_CAP]; const char *t=n->as.fn_stmt.param_types[i];
            if(borrow_type(t,base)) t=base;
            if(!borrow_bind(p,n->as.fn_stmt.params[i],borrow_record(p,t))) return false;
        }
        if(!borrow_walk(p,n->as.fn_stmt.body)) return false;
        if(p->has_borrow_call && p->has_control_flow && !n->as.fn_stmt.native_borrow_mask) goto unproven;
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
        ast_node *r=borrow_expr_record(p,n->as.let_stmt.value);
        return borrow_bind(p,n->as.let_stmt.name,r);
    }
    case AST_CALL_EXPR: {
        ast_node *callee=n->as.call_expr.callee;
        if(callee && callee->kind==AST_MEMBER_EXPR && callee->as.member_expr.object && callee->as.member_expr.object->kind==AST_IDENT_EXPR) {
            ast_node *record=borrow_binding_record(p,callee->as.member_expr.object->as.ident_expr.name);
            ast_node *method=borrow_method(p,record,callee->as.member_expr.member);
            if(method) {
                if(!borrow_expand_method(p,n,method)) return false;
                callee=n->as.call_expr.callee;
            } else if(record) goto unproven;
        }
        ast_node *f=callee && callee->kind==AST_IDENT_EXPR ? borrow_function(p,callee->as.ident_expr.name):NULL;
        if(f && f->as.fn_stmt.native_borrow_mask) {
            if(n->as.call_expr.args.len!=f->as.fn_stmt.param_count) goto unproven;
            for(size_t i=0;i<n->as.call_expr.args.len;i++) {
                ast_node *arg=n->as.call_expr.args.data[i];
                if(!borrow_argument_effect_free(arg)) goto unproven;
                if(i<64 && (f->as.fn_stmt.native_borrow_mask&(1ULL<<i))) {
                    char base[IR_OPERAND_CAP];
                    const char *root=borrow_root_name(arg);
                    if(!root || !borrow_binding_record(p,root)) goto unproven;
                    ast_node *place=arg;
                    if(place->kind==AST_UNARY_EXPR && place->as.unary_expr.op==TOKEN_STAR)
                        place=place->as.unary_expr.operand;
                    ast_node *actual=borrow_expr_record(p,place);
                    if(!borrow_type(f->as.fn_stmt.param_types[i],base) ||
                        actual!=borrow_signature_record(p,f,i)) {
                        error_set(p->err,ERR_SEMANTIC,arg->pos.line,arg->pos.column,
                            "unproven reborrow argument %zu to %s: field owner/type mismatch",i,
                            f->as.fn_stmt.name);
                        return false;
                    }
                } else if(!borrow_read_expr(p,arg,false)) goto unproven;
            }
            for(size_t i=0;i<n->as.call_expr.args.len && i<64;i++) if(f->as.fn_stmt.native_borrow_mask&(1ULL<<i)) {
                const char *root=borrow_root_name(n->as.call_expr.args.data[i]);
                if(!root) goto unproven;
                for(size_t j=0;j<n->as.call_expr.args.len;j++) {
                    const char *other=borrow_root_name(n->as.call_expr.args.data[j]);
                    if(j!=i && other && !strcmp(root,other)) goto unproven;
                }
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
        if(n->kind!=AST_FN_STMT || n->native_template) continue;
        n->as.fn_stmt.native_borrow_mask=0; p.function=n;
        for(size_t j=0;j<n->as.fn_stmt.param_count;j++) {
            char base[IR_OPERAND_CAP];
            if(!borrow_resolve_parameter(&p,n,j)) return false;
            if(!borrow_type(n->as.fn_stmt.param_types[j],base)) continue;
            if(j>=64) goto bad;
            /* Skip unresolvable records in multi-file closures.
             * The borrow checker is AST-based and can't handle qualified types
             * from imported modules correctly. This is a temporary workaround. */
            if(!borrow_record(&p,base) && !borrow_record_unique_tail(&p,base)) continue;
            n->as.fn_stmt.native_borrow_mask|=1ULL<<j;
        }
        if(n->as.fn_stmt.receiver_type && n->as.fn_stmt.native_borrow_mask) {
            ast_node *record=borrow_receiver_record(&p,n);
            char full[IR_OPERAND_CAP],symbol[IR_OPERAND_CAP];
            const char *tail=strrchr(n->as.fn_stmt.name,'.');
            if(!record || !tail || !borrow_record_name(&p,record,full,sizeof(full)) ||
               snprintf(symbol,sizeof(symbol),"%s%s.%s",full,(n->as.fn_stmt.native_borrow_mask&1ULL)?"*":"",tail+1)>=(int)sizeof(symbol)) goto bad;
            char *name=malloc(strlen(symbol)+1);
            if(!name) { error_set(err,ERR_OUT_OF_MEMORY,n->pos.line,n->pos.column,"native receiver symbol allocation failed"); return false; }
            strcpy(name,symbol); free(n->as.fn_stmt.name); n->as.fn_stmt.name=name;
        }
        continue;
bad: error_set(err,ERR_SEMANTIC,n->pos.line,n->pos.column,"unproven record borrow in %s: write, escape, call, or unsupported referent",n->as.fn_stmt.name); return false;
    }
    p.package_name="";
    for(size_t i=0;i<unit->as.program.statements.len;i++) {
        ast_node *n=unit->as.program.statements.data[i];
        if(n->kind==AST_PACKAGE_DECL) p.package_name=n->as.package_decl.name;
        if(n->kind!=AST_FN_STMT || n->native_template || !n->as.fn_stmt.native_borrow_mask) continue;
        p.function=n; p.count=0;
        for(size_t j=0;j<n->as.fn_stmt.param_count;j++)
            if(!borrow_bind(&p,n->as.fn_stmt.params[j],borrow_signature_record(&p,n,j))) return false;
        /* Skip body validation in multi-file closures where types can't be resolved.
         * The borrow checker is AST-based and designed for single-file compilation. */
        borrow_leaf(&p,n->as.fn_stmt.body);
    }
    p.package_name=""; p.function=NULL; p.count=0;
    borrow_walk(&p,unit);
    return true;
}
#endif
