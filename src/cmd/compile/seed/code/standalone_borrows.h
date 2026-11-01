/* Independently prove native IR borrow contracts before invoking native tools.
 * Callers and callees share the CFG type/ownership proof, including projected
 * reborrows. A field path never manufactures ownership for its root. */
static bool standalone_borrow_scalar(const char *t) {
    return t && (!strcmp(t,"int") || !strcmp(t,"bool") || !strcmp(t,"byte") || !strcmp(t,"()"));
}
static int standalone_transfer_compare(const void *left,const void *right) {
    const standalone_ins *a=*(const standalone_ins *const *)left;
    const standalone_ins *b=*(const standalone_ins *const *)right;
    int result=strcmp(a->result,b->result);
    return result?result:strcmp(a->operand1,b->operand1);
}
/* Metadata is immutable after loading. Index the original records rather than
 * rewriting them: callers still reject duplicate descriptors, even identical
 * ones, and NULL parameter queries still require one descriptor in total. */
static bool standalone_build_transfer_index(standalone_module *m,compile_error *err) {
    free(m->transfer_index);
    m->transfer_index=NULL;
    m->transfer_count=0;
    for(size_t i=0;i<m->ir.len;i++)
        if(!strcmp(m->ir.ins[i].op,"NOP")) m->transfer_count++;
    if(!m->transfer_count) return true;
    m->transfer_index=malloc(m->transfer_count*sizeof(*m->transfer_index));
    if(!m->transfer_index) {
        error_set(err,ERR_OUT_OF_MEMORY,0,0,"native transfer index allocation failed");
        return false;
    }
    size_t next=0;
    for(size_t i=0;i<m->ir.len;i++)
        if(!strcmp(m->ir.ins[i].op,"NOP")) m->transfer_index[next++]=&m->ir.ins[i];
    qsort(m->transfer_index,m->transfer_count,sizeof(*m->transfer_index),standalone_transfer_compare);
    return true;
}
static int standalone_transfer_key(const standalone_ins *x,const char *prefix,size_t n,const char *fn,const char *param) {
    int result=strncmp(x->result,prefix,n);
    if(!result) result=strcmp(x->result+n,fn);
    if(!result && param) result=strcmp(x->operand1,param);
    return result;
}
static const char *standalone_transfer(const standalone_module *m,const char *prefix,const char *fn,const char *param) {
    size_t n=strlen(prefix),first=0,last=m->transfer_count;
    while(first<last) {
        size_t middle=first+(last-first)/2;
        if(standalone_transfer_key(m->transfer_index[middle],prefix,n,fn,param)<0) first=middle+1;
        else last=middle;
    }
    if(first==m->transfer_count || standalone_transfer_key(m->transfer_index[first],prefix,n,fn,param)) return NULL;
    if(first+1<m->transfer_count && !standalone_transfer_key(m->transfer_index[first+1],prefix,n,fn,param)) return NULL;
    return m->transfer_index[first]->operand2;
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
            if(r<0 || n<2 || raw[n-1]!='*' || strpbrk(raw,"& ")) goto bad;
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
    for(size_t g=0;g<m->global_count;g++) {
        standalone_global *global=&m->globals[g];
        standalone_function *init=standalone_borrow_function(m,global->initializer);
        const char *type=init?standalone_transfer(m,"return-transfer:",init->name,NULL):NULL;
        if(!init || !type || strcmp(type,global->type) ||
           (init->begin<init->end && !strcmp(m->ir.ins[init->begin].op,"PARAM"))) goto bad;
        init->borrow_owner_needed=true;
    }
    /* Every caller of an owner-consuming function must establish its actual
     * parameter types. Propagate backwards to the native entrypoint, rather
     * than trusting an intermediate function's annotations in isolation. */
    bool changed;
    do {
        changed=false;
        for(size_t f=0;f<m->func_count;f++) {
            standalone_function *fn=&m->funcs[f]; bool needed=fn->borrow_mask!=0;
            for(size_t s=0;s<fn->slot_count;s++) if(standalone_global_index(m,fn->slots[s].name)>=0) needed=true;
            const char *result=standalone_transfer(m,"return-transfer:",fn->name,NULL);
            if(result && (!strcmp(result,"()") || !strcmp(result,"unit"))) needed=true;
            if(result && strchr(result,'[') && standalone_record_index(m,result)>=0) needed=true;
            for(size_t i=fn->begin;!needed && i<fn->end;i++) {
                standalone_ins *x=&m->ir.ins[i];
                if(!strcmp(x->op,"UNIT")) needed=true;
                if(!strcmp(x->op,"PARAM")) {
                    const char *type=standalone_transfer(m,"param-transfer:",fn->name,x->result);
                    if(type && (!strcmp(type,"()") || !strcmp(type,"unit"))) needed=true;
                    if(type && strchr(type,'[') && standalone_record_index(m,type)>=0) needed=true;
                }
                size_t len=strlen(x->result);
                if(!strcmp(x->op,"MOV") && len>7 && !strcmp(x->result+len-7,".__type") && strchr(x->operand1,'[')) needed=true;
                if(!strcmp(x->op,"ARG") && !strcmp(x->operand1,"mutable_borrow")) needed=true;
                if(!strcmp(x->op,"CALL")) {
                    if(!strcmp(x->operand1,"__vec_push") || !strcmp(x->operand1,"__vec_len")) needed=true;
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
