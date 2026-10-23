/* Independently prove native IR borrow contracts before invoking native tools.
 * Callers and callees share the CFG type/ownership proof, including projected
 * reborrows. A field path never manufactures ownership for its root. */
static bool standalone_borrow_scalar(const char *t) {
    return t && (!strcmp(t,"int") || !strcmp(t,"bool") || !strcmp(t,"byte") || !strcmp(t,"()"));
}
static const char *standalone_transfer(const standalone_module *m,const char *prefix,const char *fn,const char *param) {
    const char *value=NULL;
    size_t n=strlen(prefix);
    for(size_t i=0;i<m->ir.len;i++) {
        const standalone_ins *x=&m->ir.ins[i];
        if(strcmp(x->op,"NOP") || strncmp(x->result,prefix,n) || strcmp(x->result+n,fn) || (param && strcmp(param,x->operand1))) continue;
        if(value) return NULL; /* Duplicate descriptors are not proof. */
        value=x->operand2;
    }
    return value;
}
static standalone_function *standalone_borrow_function(standalone_module *m,const char *name) {
    standalone_function *found=NULL;
    for(size_t i=0;i<m->func_count;i++) if(!strcmp(m->funcs[i].name,name)) {
        if(found) return NULL;
        found=&m->funcs[i];
    }
    return found;
}
/* CALL validation must resolve exactly the same symbol as emission, including
 * package-qualified and normalized names. Descriptor names stay exact. */
static standalone_function *standalone_borrow_callee(standalone_module *m,const char *name) {
    if(runtime_callee(name)) return NULL;
    const char *resolved=defined_function_name(m,name);
    return resolved?standalone_borrow_function(m,resolved):NULL;
}
static bool standalone_borrow_metadata_proven(standalone_module *m,const standalone_ins *x) {
    if(strncmp(x->result,"param-transfer:",15)) return false;
    standalone_function *fn=standalone_borrow_function(m,x->result+15);
    if(!fn) return false;
    size_t p=0;
    for(size_t i=fn->begin;i<fn->end && !strcmp(m->ir.ins[i].op,"PARAM");i++,p++)
        if(!strcmp(x->operand1,m->ir.ins[i].result)) return p<64 && (fn->borrow_mask&(1ULL<<p));
    return false;
}
#include "standalone_borrow_flow.h"
static bool standalone_validate_borrows(standalone_module *m,compile_error *err) {
    size_t at=0;
    /* Bind descriptors to real PARAM records; validate the entire referent. */
    for(size_t f=0;f<m->func_count;f++) {
        standalone_function *fn=&m->funcs[f]; size_t p=0;
        for(size_t i=fn->begin;i<fn->end && !strcmp(m->ir.ins[i].op,"PARAM");i++,p++) {
            standalone_ins *x=&m->ir.ins[i];
            if(!strcmp(x->operand1,"_") || !*x->operand1) continue;
            at=i;
            if(strcmp(x->operand1,"mutable_borrow") || p>=64 || runtime_callee(fn->name) ||
                strstr(fn->name,"env_get") || !strcmp(fn->name,"make")) goto bad;
            const char *schema=standalone_transfer(m,"borrow-param:",fn->name,x->result);
            const char *raw=standalone_transfer(m,"param-transfer:",fn->name,x->result);
            int r=schema?standalone_record_index(m,schema):-1;
            size_t n=raw?strlen(raw):0;
            if(r<0 || n<2 || raw[n-1]!='*' || strpbrk(raw,"& []")) goto bad;
            const char *base=strrchr(schema,'.'); base=base?base+1:schema;
            if(!((strlen(base)==n-1 && !strncmp(base,raw,n-1)) || (strlen(schema)==n-1 && !strncmp(schema,raw,n-1)))) goto bad;
            if(!standalone_validate_record_schema(m,r,err)) return false;
            fn->borrow_mask|=1ULL<<p; fn->borrow_schema[p]=r;
        }
    }
    /* A descriptor cannot float free of a function/parameter or be ignored. */
    for(size_t i=0;i<m->ir.len;i++) {
        standalone_ins *x=&m->ir.ins[i];
        if(strcmp(x->op,"NOP") || strncmp(x->result,"borrow-param:",13)) continue;
        at=i;
        standalone_function *fn=standalone_borrow_function(m,x->result+13);
        if(!fn) goto bad;
        size_t p=0; bool found=false;
        for(size_t j=fn->begin;j<fn->end && !strcmp(m->ir.ins[j].op,"PARAM");j++,p++)
            if(!strcmp(x->operand1,m->ir.ins[j].result) && p<64 && (fn->borrow_mask&(1ULL<<p))) found=true;
        if(!found) goto bad;
    }
    /* Every caller of an owner-consuming function must establish its actual
     * parameter types. Propagate backwards to the native entrypoint, rather
     * than trusting an intermediate function's annotations in isolation. */
    bool changed;
    do {
        changed=false;
        for(size_t f=0;f<m->func_count;f++) {
            standalone_function *fn=&m->funcs[f]; bool needed=fn->borrow_mask!=0;
            for(size_t i=fn->begin;!needed && i<fn->end;i++) {
                standalone_ins *x=&m->ir.ins[i];
                if(!strcmp(x->op,"ARG") && !strcmp(x->operand1,"mutable_borrow")) needed=true;
                if(!strcmp(x->op,"CALL")) {
                    standalone_function *target=standalone_borrow_callee(m,x->operand1);
                    if(target && (target->borrow_mask || target->borrow_owner_needed)) needed=true;
                }
            }
            if(needed && !fn->borrow_owner_needed) { fn->borrow_owner_needed=true; changed=true; }
        }
    } while(changed);
    for(size_t f=0;f<m->func_count;f++) {
        standalone_function *fn=&m->funcs[f];
        if(!fn->borrow_owner_needed) continue;
        /* The standalone startup supplies raw argc/argv, not tagged language
         * parameters. Borrowing programs obtain arguments via host_args(). */
        if(!strcmp(fn->name,"main")) for(size_t i=fn->begin;i<fn->end;i++)
            if(!strcmp(m->ir.ins[i].op,"PARAM")) { at=i; goto bad; }
        if(!standalone_validate_borrow_flow(m,fn,err)) return false;
    }
    return true;
bad:
    error_set(err,ERR_SEMANTIC,0,0,"unproven native record borrow at IR record %zu",at+2); return false;
}
