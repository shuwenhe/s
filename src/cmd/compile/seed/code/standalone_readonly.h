/* A pure callee can observe a shared value only while it neither mutates nor
 * exposes an alias. MOV and RET still snapshot: owned copies and returned
 * values keep their ordinary independence. This never changes validation. */
static unsigned long long standalone_read_alias(standalone_function *fn,
        const unsigned long long *aliases,const char *text) {
    unsigned long long used[(STANDALONE_MAX_SLOTS+63)/64]={0},result=0;
    standalone_live_operand(fn,text,used);
    for(size_t s=0;s<fn->slot_count;s++) if(used[s/64]&(1ULL<<(s%64))) result|=aliases[s];
    return result;
}
static void standalone_analyze_readonly(standalone_module *m) {
    for(size_t f=0;f<m->func_count;f++) {
        standalone_function *fn=&m->funcs[f]; fn->readonly_params=0;
        /* A global or borrowed side effect could mutate another alias of an
         * argument, even when the parameter itself is used only for reads. */
        if(!fn->region_safe || fn->region_globals || fn->borrow_mask) continue;
        unsigned long long aliases[STANDALONE_MAX_SLOTS]={0},mask=0,forbidden=0;
        size_t p=0;
        for(size_t i=fn->begin;i<fn->end && !strcmp(m->ir.ins[i].op,"PARAM") && p<64;i++,p++) {
            int slot=slot_index(fn,m->ir.ins[i].result,false);
            if(slot>=0) aliases[slot]=1ULL<<p;
            mask|=1ULL<<p;
        }
        bool changed;
        do {
            changed=false;
            const char *pending[STANDALONE_MAX_PENDING_ARGS]; size_t count=0;
            for(size_t i=fn->begin;i<fn->end;i++) {
                standalone_ins *x=&m->ir.ins[i];
                unsigned long long source=standalone_read_alias(fn,aliases,x->operand1),result=0;
                if(!strcmp(x->op,"READ") || !strcmp(x->op,"INDEX_GET")) result=source;
                if(!strcmp(x->op,"MOV") && strchr(x->result,'.'))
                    forbidden|=standalone_read_alias(fn,aliases,x->result)|source;
                if(!strcmp(x->op,"INDEX_SET"))
                    forbidden|=standalone_read_alias(fn,aliases,x->result)|standalone_read_alias(fn,aliases,x->operand2);
                if(!strcmp(x->op,"ARG")) {
                    if(count==STANDALONE_MAX_PENDING_ARGS) { forbidden=~0ULL; break; }
                    pending[count++]=x->result;
                    if(!strcmp(x->operand1,"mutable_borrow")) forbidden|=standalone_read_alias(fn,aliases,x->result);
                }
                if(!strcmp(x->op,"CALL")) {
                    char *end=NULL; long argc=strtol(x->operand2,&end,10);
                    if(!end || *end || argc<0 || (size_t)argc>count) { forbidden=~0ULL; break; }
                    size_t first=count-(size_t)argc;
                    unsigned long long arguments=0;
                    for(size_t a=first;a<count;a++) arguments|=standalone_read_alias(fn,aliases,pending[a]);
                    const char *runtime=runtime_callee(x->operand1);
                    if(runtime && !strcmp(runtime,"s_index_get")) {
                        if(argc) result=standalone_read_alias(fn,aliases,pending[first]);
                    } else if(runtime && !strcmp(runtime,"s_array_append")) result=arguments;
                    else if(runtime && strcmp(runtime,"s_value_len") && strcmp(runtime,"s_string_char_at") &&
                            strcmp(runtime,"s_string_byte_at") && strcmp(runtime,"s_string_slice") &&
                            strcmp(runtime,"s_contains_text") && strcmp(runtime,"s_int_text")) forbidden|=arguments;
                    else if(!runtime && !defined_function_name(m,x->operand1)) forbidden|=arguments;
                    if(argc && (!strcmp(x->operand1,"__vec_push") || !strcmp(x->operand1,"__vec_set"))) {
                        standalone_literal path; compile_error ignored;
                        if(decode_literal(pending[first],&path,&ignored) && path.len<sizeof(path.bytes)) {
                            path.bytes[path.len]=0;
                            forbidden|=standalone_read_alias(fn,aliases,(char *)path.bytes);
                        } else forbidden=~0ULL;
                    }
                    count=first;
                }
                int slot=slot_index(fn,x->result,false);
                if(slot>=0 && (result&~aliases[slot])) { aliases[slot]|=result; changed=true; }
            }
        } while(changed);
        fn->readonly_params=mask&~forbidden;
    }
}
static bool standalone_readonly_argument(standalone_module *m,standalone_function *caller,size_t at) {
    size_t next=at+1;
    /* An earlier value must retain its evaluation-time snapshot if another
     * argument performs a computation or nested call before this CALL. */
    while(next<caller->end && !strcmp(m->ir.ins[next].op,"ARG")) next++;
    if(next==caller->end || strcmp(m->ir.ins[next].op,"CALL") || runtime_callee(m->ir.ins[next].operand1)) return false;
    char *end=NULL; long argc=strtol(m->ir.ins[next].operand2,&end,10);
    if(!end || *end || argc<=0 || (size_t)argc<next-at) return false;
    size_t parameter=(size_t)argc-(next-at);
    standalone_function *callee=standalone_borrow_callee(m,m->ir.ins[next].operand1);
    return callee && parameter<64 && (callee->readonly_params&(1ULL<<parameter));
}
