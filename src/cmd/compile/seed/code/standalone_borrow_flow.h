/* Definite-type dataflow for nonescaping borrowed callees. No package-name
 * exceptions: every reachable predecessor contributes to the type meet. */
#define BF_UNKNOWN (-1)
#define BF_INT (-2)
#define BF_STRING (-3)
#define BF_UNIT (-4)
#define BF_MAX_ARRAYS 4096
/* Type and ownership are separate lattice facts. READ aliases never acquire
 * ownership; only value snapshots/constructors/verified returns do. */
static int borrow_flow_base(int type) { return type<=-16?-type-16:type; }
static bool borrow_flow_owned(int type) { return type<=-16; }
static int borrow_flow_snapshot(int type,size_t records) {
    return type>=0 && (size_t)type<records?-type-16:type;
}
static int borrow_flow_meet(int a,int b) {
    if(a==b) return a;
    return borrow_flow_base(a)==borrow_flow_base(b)?borrow_flow_base(a):BF_UNKNOWN;
}
typedef struct borrow_flow_types {
    standalone_module *m;
    compile_error *err;
    int elements[BF_MAX_ARRAYS];
    size_t arrays;
} borrow_flow_types;
typedef struct borrow_flow_block { size_t begin,end; int successors[2]; bool reached,queued; } borrow_flow_block;
static bool standalone_validate_borrow_flow(standalone_module *,standalone_function *,compile_error *);
static int borrow_flow_record_type(borrow_flow_types *t,int record) {
    return record>=0 && standalone_validate_record_schema(t->m,record,t->err)?record:BF_UNKNOWN;
}
static int borrow_flow_array(borrow_flow_types *t,int element) {
    if(element==BF_UNKNOWN || element==BF_UNIT) return BF_UNKNOWN;
    for(size_t i=0;i<t->arrays;i++) if(t->elements[i]==element) return (int)(t->m->record_count+i);
    if(t->arrays==BF_MAX_ARRAYS) return BF_UNKNOWN;
    t->elements[t->arrays]=element;
    return (int)(t->m->record_count+t->arrays++);
}
static bool borrow_flow_is_array(borrow_flow_types *t,int type) {
    return type>=(int)t->m->record_count && (size_t)(type-(int)t->m->record_count)<t->arrays;
}
static int borrow_flow_type(borrow_flow_types *t,const char *name,const char *context,unsigned depth) {
    if(!name || depth>64) return BF_UNKNOWN;
    if(!strcmp(name,"()")) return BF_UNIT;
    if(standalone_borrow_scalar(name) || !strcmp(name,"int64") || !strcmp(name,"uint64") || !strcmp(name,"uint")) return BF_INT;
    if(!strcmp(name,"string")) return BF_STRING;
    char element[STANDALONE_TEXT_CAP];
    if(seed_array_element(name,element,sizeof(element))) return borrow_flow_array(t,borrow_flow_type(t,element,context,depth+1));
    if(strpbrk(name,"*& []")) return BF_UNKNOWN;
    int r=standalone_record_index(t->m,name);
    if(r>=0) return borrow_flow_record_type(t,r);
    if(context && !strchr(name,'.')) {
        const char *dot=strrchr(context,'.'); char qualified[STANDALONE_TEXT_CAP];
        if(dot && snprintf(qualified,sizeof(qualified),"%.*s.%s",(int)(dot-context),context,name)<(int)sizeof(qualified))
            return borrow_flow_record_type(t,standalone_record_index(t->m,qualified));
    }
    /* Raw function annotations may lack qualification; ambiguity is rejected. */
    for(size_t i=0;i<t->m->record_count;i++) {
        const char *tail=strrchr(t->m->records[i].name,'.'); tail=tail?tail+1:t->m->records[i].name;
        if(!strcmp(tail,name)) { if(r>=0) return BF_UNKNOWN; r=(int)i; }
    }
    return borrow_flow_record_type(t,r);
}
static int borrow_flow_field(borrow_flow_types *t,int record,const char *field,size_t length) {
    if(record<0 || record>=(int)t->m->record_count) return BF_UNKNOWN;
    standalone_record_schema *r=&t->m->records[record];
    for(size_t i=0;i<r->count;i++) if(strlen(r->fields[i].name)==length && !strncmp(r->fields[i].name,field,length))
        return borrow_flow_type(t,r->fields[i].type,r->name,0);
    return BF_UNKNOWN;
}
static int borrow_flow_value_depth(borrow_flow_types *t,standalone_function *fn,int *state,const char *value,unsigned nesting);
static int borrow_flow_array_value(borrow_flow_types *t,standalone_function *fn,int *state,const char *value,unsigned nesting) {
    size_t length=strlen(value);
    if(length<2 || value[length-1]!=']' || nesting>64) return BF_UNKNOWN;
    const char *start=value+1,*end=value+length-1;
    int depth=0,element=BF_UNKNOWN; bool quoted=false,escaped=false;
    for(const char *p=start;p<=end;p++) {
        bool separator=p==end || (*p==',' && !quoted && !depth);
        if(separator) {
            char item[STANDALONE_TEXT_CAP];
            const char *first=start,*last=p;
            while(first<last && isspace((unsigned char)*first)) first++;
            while(last>first && isspace((unsigned char)last[-1])) last--;
            size_t n=(size_t)(last-first);
            if(!n || n>=sizeof(item)) return BF_UNKNOWN;
            memcpy(item,first,n); item[n]=0;
            /* Arrays hold values, never raw borrowed handles. */
            for(size_t param=0;param<64 && param<fn->slot_count;param++) {
                if(!(fn->borrow_mask&(1ULL<<param))) continue;
                size_t at=fn->begin+param;
                if(at<fn->end && !strcmp(t->m->ir.ins[at].op,"PARAM") && !strcmp(item,t->m->ir.ins[at].result)) return BF_UNKNOWN;
            }
            int type=borrow_flow_value_depth(t,fn,state,item,nesting+1);
            if(type==BF_UNKNOWN || (element!=BF_UNKNOWN && type!=element)) return BF_UNKNOWN;
            element=type; start=p+1;
        } else if(quoted) {
            if(escaped) escaped=false;
            else if(*p=='\\') escaped=true;
            else if(*p=='"') quoted=false;
        } else if(*p=='"') quoted=true;
        else if(*p=='[') depth++;
        else if(*p==']') { if(!depth) return BF_UNKNOWN; depth--; }
    }
    if(depth || quoted) return BF_UNKNOWN;
    return borrow_flow_array(t,element);
}
static int borrow_flow_value_depth(borrow_flow_types *t,standalone_function *fn,int *state,const char *value,unsigned nesting) {
    if(nesting>64) return BF_UNKNOWN;
    if(value[0]=='[') return borrow_flow_array_value(t,fn,state,value,nesting);
    if(is_integer(value)) return BF_INT;
    if(is_string_literal(value)) return BF_STRING;
    const char *dot=strchr(value,'.');
    if(!dot) { int s=slot_index(fn,value,false); return s<0?BF_UNKNOWN:borrow_flow_base(state[s]); }
    char root[STANDALONE_TEXT_CAP]; size_t n=(size_t)(dot-value);
    if(n>=sizeof(root)) return BF_UNKNOWN;
    memcpy(root,value,n); root[n]=0;
    int slot=slot_index(fn,root,false), type=slot<0?BF_UNKNOWN:borrow_flow_base(state[slot]);
    while(dot) {
        const char *next=strchr(dot+1,'.'); size_t len=next?(size_t)(next-dot-1):strlen(dot+1);
        type=borrow_flow_field(t,type,dot+1,len); dot=next;
    }
    return type;
}
static int borrow_flow_value(borrow_flow_types *t,standalone_function *fn,int *state,const char *value) {
    return borrow_flow_value_depth(t,fn,state,value,0);
}
static bool borrow_flow_raw(standalone_function *fn,bool *borrowed,const char *value) {
    int s=slot_index(fn,value,false);
    return !strchr(value,'.') && s>=0 && borrowed[s];
}
/* Parent and child paths share an exclusive owner for this restricted ABI. */
static bool borrow_flow_same_root(const char *a,const char *b) {
    size_t na=strcspn(a,"."),nb=strcspn(b,".");
    return na==nb && !strncmp(a,b,na);
}
static bool borrow_flow_place_owned(standalone_function *fn,int *state,bool *borrowed,const char *value) {
    char root[STANDALONE_TEXT_CAP]; size_t n=strcspn(value,".");
    if(!n || n>=sizeof(root)) return false;
    memcpy(root,value,n); root[n]=0;
    int slot=slot_index(fn,root,false);
    return slot>=0 && (borrowed[slot] || borrow_flow_owned(state[slot]));
}
static bool borrow_flow_literal(const char *value,char *text,size_t cap,compile_error *err) {
    standalone_literal lit;
    if(!is_string_literal(value) || !decode_literal(value,&lit,err) || lit.len>=cap || memchr(lit.bytes,0,lit.len)) return false;
    memcpy(text,lit.bytes,lit.len); text[lit.len]=0; return true;
}
static int borrow_flow_call(borrow_flow_types *t,standalone_function *fn,int *state,
        const char *name,int *args,const char **sources,bool *reborrows,size_t count,compile_error *err) {
    const char *runtime=runtime_callee(name);
    for(size_t i=0;i<count;i++) if(reborrows[i] && (runtime || !strcmp(name,"make"))) return BF_UNKNOWN;
    if(!strcmp(name,"make")) {
        char type[STANDALONE_TEXT_CAP];
        if(count!=2 || args[0]!=BF_STRING || args[1]!=BF_INT || !borrow_flow_literal(sources[0],type,sizeof(type),err)) return BF_UNKNOWN;
        int result=borrow_flow_type(t,type,NULL,0);
        return borrow_flow_is_array(t,result)?result:BF_UNKNOWN;
    }
    if(!strcmp(name,"__vec_len")) {
        char path[STANDALONE_TEXT_CAP];
        if(count!=1 || !borrow_flow_literal(sources[0],path,sizeof(path),err)) return BF_UNKNOWN;
        int value=borrow_flow_value(t,fn,state,path);
        return borrow_flow_is_array(t,value)?BF_INT:BF_UNKNOWN;
    }
    if(runtime) {
        /* Ordinary compiler callers may perform I/O between borrows. These
         * services consume scalar/string values, never record handles. Keep
         * their concrete ABI facts instead of treating their results as
         * unknown just because the original leaf proof did not need them. */
        if(!strcmp(runtime,"s_host_args_value")) return count==0?borrow_flow_array(t,BF_STRING):BF_UNKNOWN;
        if(!strcmp(runtime,"s_eprintln_value")) return count==1 && args[0]==BF_STRING?BF_UNIT:BF_UNKNOWN;
        if(!strcmp(runtime,"s_read_source_value") || !strcmp(runtime,"s_read_file_value") || !strcmp(runtime,"s_make_temp_dir_value"))
            return count==1 && args[0]==BF_STRING?BF_STRING:BF_UNKNOWN;
        if(!strcmp(runtime,"s_runtime_env_get")) return count==2 && args[0]==BF_STRING && args[1]==BF_STRING?BF_STRING:BF_UNKNOWN;
        if(!strcmp(runtime,"s_write_file_value") || !strcmp(runtime,"s_host_same_file") || !strcmp(runtime,"s_host_rename_file"))
            return count==2 && args[0]==BF_STRING && args[1]==BF_STRING?BF_INT:BF_UNKNOWN;
        if(!strcmp(runtime,"s_make_executable_value")) return count==1 && args[0]==BF_STRING?BF_INT:BF_UNKNOWN;
        if(!strcmp(runtime,"s_host_run_argv"))
            return count==1 && borrow_flow_is_array(t,args[0]) && t->elements[args[0]-(int)t->m->record_count]==BF_STRING?BF_INT:BF_UNKNOWN;
        if(!strcmp(runtime,"s_byte_string_value")) return count==1 && args[0]==BF_INT?BF_STRING:BF_UNKNOWN;
        if(!strcmp(runtime,"s_value_len")) return count==1 && (args[0]==BF_STRING || borrow_flow_is_array(t,args[0]))?BF_INT:BF_UNKNOWN;
        if(!strcmp(runtime,"s_string_byte_at")) return count==2 && args[0]==BF_STRING && args[1]==BF_INT?BF_INT:BF_UNKNOWN;
        if(!strcmp(runtime,"s_string_char_at")) return count==2 && args[0]==BF_STRING && args[1]==BF_INT?BF_STRING:BF_UNKNOWN;
        if(!strcmp(runtime,"s_string_slice")) return count==3 && args[0]==BF_STRING && args[1]==BF_INT && args[2]==BF_INT?BF_STRING:BF_UNKNOWN;
        if(!strcmp(runtime,"s_int_text")) return count==1 && args[0]==BF_INT?BF_STRING:BF_UNKNOWN;
        if(!strcmp(runtime,"s_index_get")) return count==2 && borrow_flow_is_array(t,args[0]) && args[1]==BF_INT?t->elements[args[0]-(int)t->m->record_count]:BF_UNKNOWN;
        if(!strcmp(runtime,"s_array_append")) return count==2 && borrow_flow_is_array(t,args[0]) && args[1]==t->elements[args[0]-(int)t->m->record_count]?args[0]:BF_UNKNOWN;
        return BF_UNKNOWN; /* Unknown/resource-bearing service contracts fail closed. */
    }
    standalone_function *target=standalone_borrow_callee(t->m,name);
    if(!target || !standalone_validate_borrow_flow(t->m,target,err)) return BF_UNKNOWN;
    size_t p=0;
    for(size_t i=target->begin;i<target->end && !strcmp(t->m->ir.ins[i].op,"PARAM");i++,p++) {
        if(p>=count) return BF_UNKNOWN;
        const char *type=standalone_transfer(t->m,"param-transfer:",target->name,t->m->ir.ins[i].result);
        bool expected=p<64 && (target->borrow_mask&(1ULL<<p));
        if(expected!=reborrows[p]) return BF_UNKNOWN;
        int parameter=expected?target->borrow_schema[p]:borrow_flow_type(t,type,NULL,0);
        if(args[p]!=parameter || args[p]==BF_UNKNOWN) return BF_UNKNOWN;
        if(expected) for(size_t j=0;j<count;j++)
            if(j!=p && borrow_flow_same_root(sources[p],sources[j])) return BF_UNKNOWN;
    }
    if(p!=count) return BF_UNKNOWN;
    return borrow_flow_type(t,standalone_transfer(t->m,"return-transfer:",target->name,NULL),NULL,0);
}
static bool borrow_flow_transfer(borrow_flow_types *t,standalone_function *fn,borrow_flow_block *b,
        int *state,bool *borrowed,bool unreachable,compile_error *err,size_t *failure) {
    int args[64]; const char *sources[64]; bool reborrows[64]; size_t argc=0;
    int return_type=borrow_flow_type(t,standalone_transfer(t->m,"return-transfer:",fn->name,NULL),NULL,0);
    if(return_type==BF_UNKNOWN) return false;
    for(size_t i=b->begin;i<b->end;i++) {
        standalone_ins *x=&t->m->ir.ins[i]; *failure=i;
        int dst=slot_index(fn,x->result,false), result=BF_UNKNOWN;
        if(!strcmp(x->op,"PARAM")) {
            for(size_t j=fn->begin;j<i;j++) if(strcmp(t->m->ir.ins[j].op,"PARAM")) return false;
            continue;
        }
        if(!strcmp(x->op,"LABEL") || !strcmp(x->op,"NOP") || !strcmp(x->op,"JUMP")) continue;
        if(!strcmp(x->op,"MOV")) {
            size_t n=strlen(x->result);
            if(n>7 && !strcmp(x->result+n-7,".__type")) {
                char root[STANDALONE_TEXT_CAP],type[STANDALONE_TEXT_CAP]; memcpy(root,x->result,n-7); root[n-7]=0;
                int s=slot_index(fn,root,false);
                if(s<0 || i==fn->begin || borrowed[s] || !borrow_flow_literal(x->operand1,type,sizeof(type),err)) return false;
                standalone_ins *prev=&t->m->ir.ins[i-1]; char alias[STANDALONE_TEXT_CAP];
                int r=standalone_record_index(t->m,type);
                if(r<0 || strcmp(prev->op,"MOV") || strcmp(prev->result,root) || !borrow_flow_literal(prev->operand1,alias,sizeof(alias),err) || strcmp(alias,root) || borrow_flow_base(state[s])!=r) return false;
                continue;
            }
            if(borrow_flow_raw(fn,borrowed,x->operand1)) return false;
            result=borrow_flow_value(t,fn,state,x->operand1);
            if(i+1<fn->end && is_string_literal(x->operand1)) {
                standalone_ins *next=&t->m->ir.ins[i+1]; char key[STANDALONE_TEXT_CAP],name[STANDALONE_TEXT_CAP],alias[STANDALONE_TEXT_CAP];
                if(snprintf(key,sizeof(key),"%s.__type",x->result)>=(int)sizeof(key)) return false;
                if(!strcmp(next->op,"MOV") && !strcmp(next->result,key)) {
                    if(!borrow_flow_literal(x->operand1,alias,sizeof(alias),err) || strcmp(alias,x->result) || !borrow_flow_literal(next->operand1,name,sizeof(name),err)) return false;
                    result=standalone_record_index(t->m,name);
                    if(result<0 || !standalone_validate_record_schema(t->m,result,err)) return false;
                }
            }
            if(strchr(x->result,'.')) {
                int expected=borrow_flow_value(t,fn,state,x->result);
                if(expected==BF_UNKNOWN || result!=expected) return false;
                continue;
            }
        } else if(!strcmp(x->op,"ARG")) {
            bool reborrow=!strcmp(x->operand1,"mutable_borrow");
            if(argc==64 || (!reborrow && strcmp(x->operand1,"_") && *x->operand1) ||
               (!reborrow && borrow_flow_raw(fn,borrowed,x->result))) return false;
            if(reborrow) {
                if(!borrow_flow_place_owned(fn,state,borrowed,x->result)) return false;
            }
            reborrows[argc]=reborrow;
            args[argc]=borrow_flow_value(t,fn,state,x->result); sources[argc++]=x->result;
            if(args[argc-1]==BF_UNKNOWN) return false;
            continue;
        } else if(!strcmp(x->op,"CALL")) {
            char *end; long n=strtol(x->operand2,&end,10);
            if(*end || n<0 || (size_t)n>argc) return false;
            size_t first=argc-(size_t)n;
            /* A pending outer exclusive argument must not overlap a nested
             * call. Source borrow arguments are effect-free as well. */
            for(size_t a=0;a<first;a++) if(reborrows[a]) return false;
            result=borrow_flow_call(t,fn,state,x->operand1,args+first,sources+first,reborrows+first,(size_t)n,err);
            argc=first;
        } else if(!strcmp(x->op,"ARRAY_NEW")) {
            if(!seed_array_new_valid(x->operand1,x->operand2)) return false;
            result=borrow_flow_type(t,x->operand1,NULL,0);
        } else if(!strcmp(x->op,"INDEX_SET")) {
            int array=borrow_flow_value(t,fn,state,x->result);
            if(!borrow_flow_is_array(t,array) || borrow_flow_value(t,fn,state,x->operand1)!=BF_INT || borrow_flow_raw(fn,borrowed,x->operand2) || borrow_flow_value(t,fn,state,x->operand2)!=t->elements[array-(int)t->m->record_count]) return false;
            continue;
        } else if(!strcmp(x->op,"READ")) {
            char index[STANDALONE_TEXT_CAP]; int array=borrow_flow_value(t,fn,state,x->operand1);
            if(!borrow_flow_is_array(t,array) || !parse_index_projection(x->operand2,index,sizeof(index)) || borrow_flow_value(t,fn,state,index)!=BF_INT) return false;
            result=t->elements[array-(int)t->m->record_count];
        } else if(!strcmp(x->op,"RET")) {
            if(return_type==BF_UNIT && (!*x->result || !strcmp(x->result,"_"))) continue;
            int value=borrow_flow_value(t,fn,state,x->result);
            if(borrow_flow_raw(fn,borrowed,x->result) || (value!=return_type && !(return_type==BF_UNIT && value==BF_INT) && !(unreachable && is_integer(x->result)))) return false;
            continue;
        } else if(!strcmp(x->op,"JUMP_IF_FALSE")) {
            if(argc || borrow_flow_value(t,fn,state,x->operand1)!=BF_INT) return false;
            continue;
        } else if(!strcmp(x->op,"ADD") || !strncmp(x->op,"CMP_",4) || !strcmp(x->op,"SUB") || !strcmp(x->op,"MUL") || !strcmp(x->op,"DIV") || !strcmp(x->op,"MOD") || !strcmp(x->op,"BAND") || !strcmp(x->op,"BOR") || !strcmp(x->op,"BXOR") || !strcmp(x->op,"SHL") || !strcmp(x->op,"SHR")) {
            if(borrow_flow_raw(fn,borrowed,x->operand1) || borrow_flow_raw(fn,borrowed,x->operand2)) return false;
            int left=borrow_flow_value(t,fn,state,x->operand1),right=borrow_flow_value(t,fn,state,x->operand2);
            if(left==BF_INT && right==BF_INT) result=BF_INT;
            else if(left==BF_STRING && right==BF_STRING && (!strcmp(x->op,"ADD") || !strncmp(x->op,"CMP_",4))) result=!strcmp(x->op,"ADD")?BF_STRING:BF_INT;
            else return false;
        } else return false;
        if(result==BF_UNKNOWN || dst<0 || borrowed[dst]) return false;
        state[dst]=(!strcmp(x->op,"MOV") || (!strcmp(x->op,"CALL") && !runtime_callee(x->operand1)))?
            borrow_flow_snapshot(result,t->m->record_count):result;
    }
    return argc==0;
}
static bool standalone_validate_borrow_flow(standalone_module *m,standalone_function *fn,compile_error *err) {
    if(fn->borrow_flow_state) return true; /* A recursive value-call SCC is checked body by body. */
    fn->borrow_flow_state=1;
    size_t n=fn->end-fn->begin,slots=fn->slot_count,at=fn->begin;
    bool *leaders=calloc(n+1,sizeof(bool)),*borrowed=calloc(slots?slots:1,sizeof(bool));
    int *mapping=malloc((n+1)*sizeof(int)),*initial=malloc((slots?slots:1)*sizeof(int));
    borrow_flow_block *blocks=calloc(n+1,sizeof(*blocks)); int *rows=NULL,*state=NULL,*queue=NULL;
    bool ok=false; size_t count=0;
    borrow_flow_types types={0}; types.m=m; types.err=err;
    if(!leaders || !mapping || !initial || !borrowed || !blocks || !n) goto done;
    leaders[0]=true;
    for(size_t i=0;i<n;i++) {
        standalone_ins *x=&m->ir.ins[fn->begin+i];
        if(!strcmp(x->op,"LABEL")) leaders[i]=true;
        if((!strcmp(x->op,"JUMP") || !strcmp(x->op,"JUMP_IF_FALSE") || !strcmp(x->op,"RET")) && i+1<n) leaders[i+1]=true;
    }
    for(size_t i=0;i<n;i++) {
        if(leaders[i]) { if(count) blocks[count-1].end=fn->begin+i; blocks[count].begin=fn->begin+i; count++; }
        mapping[i]=(int)count-1;
    }
    blocks[count-1].end=fn->end;
    if(slots && count>16777216/slots) goto done;
    rows=malloc(count*(slots?slots:1)*sizeof(int)); state=malloc((slots?slots:1)*sizeof(int)); queue=malloc((count+1)*sizeof(int));
    if(!rows || !state || !queue) goto done;
    for(size_t s=0;s<slots;s++) initial[s]=BF_UNKNOWN;
    size_t p=0;
    for(size_t i=fn->begin;i<fn->end && !strcmp(m->ir.ins[i].op,"PARAM");i++,p++) {
        int slot=slot_index(fn,m->ir.ins[i].result,false); at=i;
        if(slot<0 || p>=64) goto done;
        borrowed[slot]=(fn->borrow_mask&(1ULL<<p))!=0;
        initial[slot]=borrowed[slot]?fn->borrow_schema[p]:borrow_flow_type(&types,standalone_transfer(m,"param-transfer:",fn->name,m->ir.ins[i].result),NULL,0);
        if(initial[slot]==BF_UNKNOWN) goto done;
        if(!borrowed[slot]) initial[slot]=borrow_flow_snapshot(initial[slot],m->record_count);
    }
    for(size_t b=0;b<count;b++) {
        borrow_flow_block *block=&blocks[b]; standalone_ins *last=&m->ir.ins[block->end-1];
        block->successors[0]=!strcmp(last->op,"RET")?-1:(b+1<count?(int)b+1:-1); block->successors[1]=-1;
        if(!strcmp(last->op,"JUMP") || !strcmp(last->op,"JUMP_IF_FALSE")) {
            int target=-1;
            for(size_t j=0;j<n;j++) if(!strcmp(m->ir.ins[fn->begin+j].op,"LABEL") && !strcmp(m->ir.ins[fn->begin+j].result,last->result)) {
                if(target>=0) { at=block->end-1; goto done; } target=mapping[j];
            }
            if(target<0) { at=block->end-1; goto done; }
            if(!strcmp(last->op,"JUMP_IF_FALSE")) block->successors[1]=block->successors[0];
            block->successors[0]=target;
        }
    }
    memcpy(rows,initial,slots*sizeof(int)); blocks[0].reached=true; blocks[0].queued=true;
    size_t head=0,tail=1; queue[0]=0;
    while(head!=tail) {
        int b=queue[head]; head=(head+1)%(count+1); blocks[b].queued=false;
        memcpy(state,rows+(size_t)b*slots,slots*sizeof(int));
        if(!borrow_flow_transfer(&types,fn,&blocks[b],state,borrowed,false,err,&at)) goto done;
        /* The emitter's implicit fallthrough result is tagged integer zero,
         * not an arbitrary declared result. Conditional final blocks also
         * have a fallthrough edge even when their jump target is valid. */
        standalone_ins *last=&m->ir.ins[blocks[b].end-1];
        if(blocks[b].end==fn->end && strcmp(last->op,"RET") && strcmp(last->op,"JUMP") &&
            borrow_flow_type(&types,standalone_transfer(m,"return-transfer:",fn->name,NULL),NULL,0)!=BF_UNIT) {
            at=blocks[b].end-1; goto done;
        }
        for(int edge=0;edge<2;edge++) {
            int next=blocks[b].successors[edge]; if(next<0) continue;
            int *row=rows+(size_t)next*slots; bool changed=!blocks[next].reached;
            if(changed) { memcpy(row,state,slots*sizeof(int)); blocks[next].reached=true; }
            else for(size_t s=0;s<slots;s++) { int meet=borrow_flow_meet(row[s],state[s]); if(meet!=row[s]) { row[s]=meet; changed=true; } }
            if(changed && !blocks[next].queued) { queue[tail]=next; tail=(tail+1)%(count+1); blocks[next].queued=true; }
        }
    }
    /* Even unreachable operations must not contain reference escapes. Locals
     * used only in unreachable code are conservatively required to be typed. */
    for(size_t b=0;b<count;b++) if(!blocks[b].reached) {
        memcpy(state,initial,slots*sizeof(int));
        if(!borrow_flow_transfer(&types,fn,&blocks[b],state,borrowed,true,err,&at)) goto done;
    }
    ok=true;
done:
    free(leaders); free(borrowed); free(mapping); free(initial); free(blocks); free(rows); free(state); free(queue);
    fn->borrow_flow_state=ok?2:0;
    if(!ok && err->code==0) error_set(err,ERR_SEMANTIC,0,0,"unproven native borrow control flow at IR record %zu",at+2);
    return ok;
}
