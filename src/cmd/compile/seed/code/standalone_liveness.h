/* Backward CFG liveness for the roots evacuated at loop backedges. Keeping
 * every slot also keeps dead AST snapshots, often dwarfing the live result. */
static void standalone_live_operand(standalone_function *fn, const char *text,
                                    unsigned long long *bits) {
    const char *p=text;
    while(*p) {
        if(*p=='"') {
            p++;
            while(*p && *p!='"') { if(*p=='\\' && p[1]) p++; p++; }
            if(*p) p++;
            continue;
        }
        if(!isalpha((unsigned char)*p) && *p!='_' && *p!='$') { p++; continue; }
        const char *start=p++;
        while(isalnum((unsigned char)*p) || *p=='_' || *p=='$' || *p=='.') p++;
        size_t length=(size_t)(p-start);
        for(size_t s=0;s<fn->slot_count;s++) {
            size_t n=strlen(fn->slots[s].name);
            if(n<=length && !strncmp(start,fn->slots[s].name,n) &&
               (n==length || start[n]=='.')) bits[s/64]|=1ULL<<(s%64);
        }
    }
}
static void standalone_live_destination(standalone_module *m, standalone_function *fn,
                                        const char *text, unsigned long long *uses,
                                        unsigned long long *defs) {
    if(record_local_projection(m,fn,text)) {
        standalone_live_operand(fn,text,uses);
        return;
    }
    int slot=slot_index(fn,text,false);
    if(slot>=0) defs[(size_t)slot/64]|=1ULL<<((size_t)slot%64);
}
static bool standalone_analyze_liveness(standalone_module *m, standalone_function *fn,
                                        compile_error *err) {
    if(!fn->region_safe || !fn->region_loop_safe || fn->integer_only || !fn->slot_count) return true;
    size_t count=fn->end-fn->begin, words=(fn->slot_count+63)/64;
    if(!count) return true;
    unsigned long long *uses=calloc(count*words,sizeof(*uses));
    unsigned long long *defs=calloc(count*words,sizeof(*defs));
    size_t *targets=malloc(count*sizeof(*targets));
    fn->live_in=calloc(count*words,sizeof(*fn->live_in));
    if(!uses || !defs || !targets || !fn->live_in) {
        free(uses); free(defs); free(targets);
        error_set(err,ERR_OUT_OF_MEMORY,0,0,"native loop liveness allocation failed");
        return false;
    }
    for(size_t i=0;i<count;i++) {
        standalone_ins *x=&m->ir.ins[fn->begin+i];
        unsigned long long *use=uses+i*words, *def=defs+i*words;
        targets[i]=count;
        if(!strcmp(x->op,"JUMP") || !strcmp(x->op,"JUMP_IF_FALSE")) {
            for(size_t j=0;j<count;j++)
                if(!strcmp(m->ir.ins[fn->begin+j].op,"LABEL") &&
                   !strcmp(m->ir.ins[fn->begin+j].result,x->result)) { targets[i]=j; break; }
            if(!strcmp(x->op,"JUMP_IF_FALSE")) standalone_live_operand(fn,x->operand1,use);
        } else if(!strcmp(x->op,"ARG")) {
            standalone_live_operand(fn,x->result,use);
            /* Vector intrinsics name their receiver with a quoted path. */
            if(is_string_literal(x->result)) {
                standalone_literal value;
                if(decode_literal(x->result,&value,err) && value.len<sizeof(value.bytes)) {
                    value.bytes[value.len]=0;
                    standalone_live_operand(fn,(char*)value.bytes,use);
                }
            }
        } else if(!strcmp(x->op,"RET")) {
            standalone_live_operand(fn,x->result,use);
        } else if(!strcmp(x->op,"INDEX_SET")) {
            standalone_live_operand(fn,x->result,use);
            standalone_live_operand(fn,x->operand1,use);
            standalone_live_operand(fn,x->operand2,use);
        } else if(strcmp(x->op,"NOP") && strcmp(x->op,"LABEL") &&
                  strcmp(x->op,"EXPORT") && strcmp(x->op,"TRAP")) {
            standalone_live_destination(m,fn,x->result,use,def);
            if(strcmp(x->op,"CALL") && strcmp(x->op,"PARAM") &&
               strcmp(x->op,"ARRAY_NEW") && strcmp(x->op,"UNIT")) {
                standalone_live_operand(fn,x->operand1,use);
                standalone_live_operand(fn,x->operand2,use);
            }
        }
    }
    bool changed;
    do {
        changed=false;
        for(size_t i=count;i-->0;) {
            standalone_ins *x=&m->ir.ins[fn->begin+i];
            bool fallthrough=strcmp(x->op,"JUMP") && strcmp(x->op,"RET") && strcmp(x->op,"TRAP");
            for(size_t w=0;w<words;w++) {
                unsigned long long out=0;
                if(fallthrough && i+1<count) out|=fn->live_in[(i+1)*words+w];
                if(targets[i]<count) out|=fn->live_in[targets[i]*words+w];
                unsigned long long in=uses[i*words+w] | (out & ~defs[i*words+w]);
                if(in!=fn->live_in[i*words+w]) { fn->live_in[i*words+w]=in; changed=true; }
            }
        }
    } while(changed);
    free(uses); free(defs); free(targets);
    return true;
}
