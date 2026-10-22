/* Independently prove native IR borrow contracts before invoking native tools.
 * Scalar=-2, unknown=-1, eligible record>=0. The proof deliberately accepts
 * typed nonescaping callees and direct, single-definition record-owner arguments. */
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
static bool standalone_borrow_metadata_proven(standalone_module *m,const standalone_ins *x) {
    if(strncmp(x->result,"param-transfer:",15)) return false;
    standalone_function *fn=standalone_borrow_function(m,x->result+15);
    if(!fn) return false;
    size_t p=0;
    for(size_t i=fn->begin;i<fn->end && !strcmp(m->ir.ins[i].op,"PARAM");i++,p++)
        if(!strcmp(x->operand1,m->ir.ins[i].result)) return p<64 && (fn->borrow_mask&(1ULL<<p));
    return false;
}
static int standalone_borrow_kind(standalone_module *m,standalone_function *fn,int *kinds,const char *value) {
    if(is_integer(value)) return -2;
    int slot=slot_index(fn,value,false);
    if(slot>=0 && !strchr(value,'.')) return kinds[slot];
    const char *dot=strchr(value,'.');
    char root[STANDALONE_TEXT_CAP];
    if(!dot || strchr(dot+1,'.') || (size_t)(dot-value)>=sizeof(root)) return -1;
    memcpy(root,value,(size_t)(dot-value)); root[dot-value]=0;
    slot=slot_index(fn,root,false);
    if(slot<0 || kinds[slot]<0) return -1;
    standalone_record_schema *r=&m->records[kinds[slot]];
    for(size_t i=0;i<r->count;i++) if(!strcmp(r->fields[i].name,dot+1))
        return r->fields[i].kind==0 ? -2 : -1;
    return -1;
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
    for(size_t f=0;f<m->func_count;f++) {
        standalone_function *fn=&m->funcs[f]; bool needed=fn->borrow_mask!=0;
        for(size_t i=fn->begin; !needed && i<fn->end;i++) {
            standalone_ins *x=&m->ir.ins[i];
            if(!strcmp(x->op,"ARG") && !strcmp(x->operand1,"mutable_borrow")) needed=true;
            if(!strcmp(x->op,"CALL")) {
                standalone_function *target=standalone_borrow_function(m,x->operand1);
                if(target && target->borrow_mask) needed=true;
            }
        }
        if(!needed) continue;
        if(fn->borrow_mask) {
            if(!standalone_validate_borrow_flow(m,fn,err)) return false;
            continue;
        }
        int kinds[STANDALONE_MAX_SLOTS], writes[STANDALONE_MAX_SLOTS];
        bool borrowed[STANDALONE_MAX_SLOTS];
        for(size_t s=0;s<fn->slot_count;s++) { kinds[s]=-1; writes[s]=0; borrowed[s]=false; }
        for(size_t i=fn->begin;i<fn->end;i++) if(!strcmp(m->ir.ins[i].op,"MOV")) {
            int slot=slot_index(fn,m->ir.ins[i].result,false);
            if(slot>=0) writes[slot]++;
        }
        struct { int kind; bool borrow; const char *root; } args[64];
        size_t argc=0,param=0; bool active=false;
        for(size_t i=fn->begin;i<fn->end;i++) {
            standalone_ins *x=&m->ir.ins[i]; at=i;
            int dst=slot_index(fn,x->result,false);
            if(active && strcmp(x->op,"ARG") && strcmp(x->op,"CALL") && strcmp(x->op,"NOP")) goto bad;
            if(!strcmp(x->op,"PARAM")) {
                if(dst<0) goto bad;
                if(param<64 && (fn->borrow_mask&(1ULL<<param))) { kinds[dst]=fn->borrow_schema[param]; borrowed[dst]=true; }
                else if(standalone_borrow_scalar(standalone_transfer(m,"param-transfer:",fn->name,x->result))) kinds[dst]=-2;
                param++; continue;
            }
            if(!strcmp(x->op,"ARG")) {
                if(argc==64) goto bad;
                bool b=!strcmp(x->operand1,"mutable_borrow");
                if(!b && strcmp(x->operand1,"_") && *x->operand1) goto bad;
                int kind=standalone_borrow_kind(m,fn,kinds,x->result);
                if(b) {
                    int slot=slot_index(fn,x->result,false);
                    if(slot<0 || kind<0 || writes[slot]>1) goto bad;
                }
                for(size_t a=0;a<argc;a++) if((b || args[a].borrow) && !strcmp(args[a].root,x->result)) goto bad;
                args[argc].kind=kind; args[argc].borrow=b; args[argc].root=x->result; argc++; active=active||b;
                if(fn->borrow_mask) goto bad; /* Leaf-only: no reference escape via calls. */
                continue;
            }
            if(!strcmp(x->op,"CALL")) {
                if(fn->borrow_mask) goto bad;
                char *end; long n=strtol(x->operand2,&end,10);
                if(*end || n<0 || (size_t)n>argc) goto bad;
                size_t first=argc-(size_t)n;
                standalone_function *target=standalone_borrow_function(m,x->operand1);
                if(target && target->borrow_mask) {
                    size_t required=0;
                    for(size_t j=target->begin;j<target->end && !strcmp(m->ir.ins[j].op,"PARAM");j++) required++;
                    if((size_t)n!=required) goto bad;
                }
                if(active && first) goto bad;
                for(size_t a=0;a<(size_t)n;a++) {
                    bool expected=target && a<64 && (target->borrow_mask&(1ULL<<a));
                    if(expected!=args[first+a].borrow || (expected && args[first+a].kind!=target->borrow_schema[a])) goto bad;
                }
                argc=first; active=false;
                if(dst>=0) kinds[dst]=-1;
                continue;
            }
            if(!strcmp(x->op,"MOV")) {
                size_t n=strlen(x->result);
                if(n>7 && !strcmp(x->result+n-7,".__type") && is_string_literal(x->operand1)) {
                    char root[STANDALONE_TEXT_CAP]; memcpy(root,x->result,n-7); root[n-7]=0;
                    int slot=slot_index(fn,root,false); standalone_literal lit;
                    if(slot<0 || i==fn->begin || !decode_literal(x->operand1,&lit,err)) goto bad;
                    standalone_ins *constructor=&m->ir.ins[i-1]; standalone_literal alias;
                    if(strcmp(constructor->op,"MOV") || strcmp(constructor->result,root) ||
                        !is_string_literal(constructor->operand1) || !decode_literal(constructor->operand1,&alias,err) ||
                        alias.len!=strlen(root) || memcmp(alias.bytes,root,alias.len)) goto bad;
                    lit.bytes[lit.len]=0;
                    int r=standalone_record_index(m,(char*)lit.bytes);
                    if(r<0 || borrowed[slot]) goto bad;
                    if(!standalone_validate_record_schema(m,r,err)) return false;
                    kinds[slot]=r; continue;
                }
                int kind=standalone_borrow_kind(m,fn,kinds,x->operand1);
                int src=slot_index(fn,x->operand1,false);
                if(fn->borrow_mask && src>=0 && borrowed[src]) goto bad;
                if(strchr(x->result,'.')) {
                    const char *dot=strchr(x->result,'.');
                    char root[STANDALONE_TEXT_CAP]; size_t len=(size_t)(dot-x->result);
                    if(len>=sizeof(root)) goto bad;
                    memcpy(root,x->result,len); root[len]=0;
                    int slot=slot_index(fn,root,false);
                    if(fn->borrow_mask && slot>=0 && borrowed[slot] && (standalone_borrow_kind(m,fn,kinds,x->result)!=-2 || kind!=-2)) goto bad;
                } else if(dst>=0) {
                    if(borrowed[dst]) goto bad;
                    kinds[dst]=kind;
                }
                continue;
            }
            if(!strcmp(x->op,"RET")) {
                int src=slot_index(fn,x->result,false);
                if(fn->borrow_mask && src>=0 && borrowed[src]) goto bad;
                continue;
            }
            if(!fn->borrow_mask && (!strcmp(x->op,"LABEL") || !strcmp(x->op,"JUMP") || !strcmp(x->op,"JUMP_IF_FALSE"))) goto bad;
            if(!strcmp(x->op,"LABEL") || !strcmp(x->op,"JUMP") || !strcmp(x->op,"NOP")) continue;
            if(!strcmp(x->op,"JUMP_IF_FALSE")) {
                if(fn->borrow_mask && standalone_borrow_kind(m,fn,kinds,x->operand1)!=-2) goto bad;
                continue;
            }
            if(!strncmp(x->op,"CMP_",4) || !strcmp(x->op,"ADD") || !strcmp(x->op,"SUB") || !strcmp(x->op,"MUL") || !strcmp(x->op,"DIV") || !strcmp(x->op,"MOD")) {
                if(fn->borrow_mask && (standalone_borrow_kind(m,fn,kinds,x->operand1)!=-2 || standalone_borrow_kind(m,fn,kinds,x->operand2)!=-2)) goto bad;
                if(dst>=0) kinds[dst]=-2;
                continue;
            }
            if(fn->borrow_mask && strcmp(x->op,"ARRAY_NEW")) goto bad;
            if(dst>=0) kinds[dst]=-1;
        }
        if(active) goto bad;
    }
    return true;
bad:
    error_set(err,ERR_SEMANTIC,0,0,"unproven native record borrow at IR record %zu",at+2); return false;
}
