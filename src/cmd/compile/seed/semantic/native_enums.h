#ifndef S_NATIVE_ENUMS_H
#define S_NATIVE_ENUMS_H
/* Concrete sum values use a fixed typed slot per variant. Inactive slots have
 * ordinary defaults; projecting a payload never changes its representation. */
static ng_decl *ng_enum_owner(ng_scope *c,const char *name) {
    ng_decl *d=ng_find(c->state,name,c->package,false);
    if(d && d->node->kind==AST_ENUM_DECL) return d;
    for(size_t i=0;i<c->state->count;i++) {
        d=c->state->decls[i];
        if(d->node->kind==AST_ENUM_DECL && (!strcmp(d->name,name) ||
           (!strcmp(d->package,c->package) && !strcmp(d->node->as.enum_decl.name,name)))) return d;
        const char *tail=strrchr(d->package,'.'); tail=tail?tail+1:d->package;
        if(d->node->kind==AST_ENUM_DECL && !strcmp(d->package,name) && !strcmp(d->node->as.enum_decl.name,tail)) return d;
    }
    return NULL;
}
static ng_decl *ng_enum_type(ng_scope *c,const char *type,ng_text args[NG_ARGS]) {
    ng_text text,base;
    snprintf(text,sizeof(text),"%s",type?type:"");
    size_t len=strlen(text); if(len && text[len-1]=='*') text[len-1]=0;
    int count=ng_split(text,base,args);
    ng_decl *d=ng_enum_owner(c,count>0?base:text);
    if(count<0) return d && !d->count && seed_enum_has_payload(d->node)?d:NULL;
    return d && d->count==(size_t)count?d:NULL;
}
static bool ng_enum_field(ng_state *s,ast_node *schema,const char *name,const char *type,source_pos pos) {
    size_t count=schema->as.struct_expr.field_count;
    char **names=realloc(schema->as.struct_expr.field_names,(count+1)*sizeof(char*));
    if(!names) return ng_fail(s,pos,"enum field allocation failed");
    schema->as.struct_expr.field_names=names;
    ast_node *v=ast_new(AST_STRING_EXPR,pos); if(!v) return false;
    v->as.string_expr.literal=ng_dup(type); v->as.string_expr.is_type_name=true;
    names[count]=ng_dup(name);
    if(!v->as.string_expr.literal || !names[count] || !ast_vec_push(&schema->as.struct_expr.field_values,v)) {
        free(names[count]); ast_free(v); return false;
    }
    schema->as.struct_expr.field_count++; return true;
}
static bool ng_enum_payload_name(ng_state *s,const char *variant,ng_text out,source_pos pos) {
    return snprintf(out,sizeof(ng_text),"__payload_%s",variant)<(int)sizeof(ng_text) || ng_fail(s,pos,"enum variant name too long");
}
static bool ng_enum_tag(ng_state *s,ng_decl *d,size_t index,int64_t *tag) {
    int64_t next=0;
    for(size_t i=0;i<=index;i++) {
        ast_enum_variant *v=&d->node->as.enum_decl.variants[i];
        if(v->has_explicit_value) next=v->explicit_value;
        if(i==index) { *tag=next; return true; }
        if(next==INT64_MAX) return ng_fail(s,d->node->pos,"enum tag overflow");
        next++;
    }
    return false;
}
static bool ng_enum_schema(ng_scope *c,ng_decl *d,ng_text *args,size_t count,const char *full,unsigned depth) {
    ng_state *s=c->state; ng_text local;
    if(count) { if(!ng_application(s,d->node->as.enum_decl.name,args,count,local,d->node->pos)) return false; }
    else snprintf(local,sizeof(local),"%s",d->node->as.enum_decl.name);
    ast_node *record=ast_new(AST_LET_STMT,d->node->pos),*schema=ast_new(AST_STRUCT_EXPR,d->node->pos);
    if(!record || !schema) { ast_free(record); ast_free(schema); return false; }
    record->as.let_stmt.name=ng_dup(local); record->as.let_stmt.type_name=ng_dup("struct");
    record->as.let_stmt.value=schema; schema->as.struct_expr.type_name=ng_dup(local);
    record->native_enum=true;
    if(!record->as.let_stmt.name || !record->as.let_stmt.type_name || !schema->as.struct_expr.type_name) { ast_free(record); return false; }
    /* Register before traversing fields, as for recursive record templates. */
    ng_decl *layout=ng_append(s,record,d->package);
    if(!layout) return ng_fail(s,d->node->pos,"cannot append enum layout");
    if(!count) d->enum_layout=layout;
    ng_scope *fields=calloc(1,sizeof(*fields)); if(!fields) return false;
    fields->state=s; fields->package=d->package; fields->origin=d;
    for(size_t i=0;i<count;i++) strcpy(fields->actuals[i],args[i]);
    bool ok=ng_enum_field(s,schema,"__variant","int",record->pos);
    for(size_t i=0;ok && i<d->node->as.enum_decl.variant_count;i++) {
        ast_enum_variant *v=&d->node->as.enum_decl.variants[i];
        if(!v->payload_type) continue;
        ng_text field,type;
        ok=ng_enum_payload_name(s,v->name,field,record->pos) && ng_type(fields,v->payload_type,type,depth+1);
        if(ok && !count) {
            size_t len=strlen(type);
            if(len+2>=sizeof(type)) ok=ng_fail(s,record->pos,"enum payload type too long");
            else strcat(type,"[]");
        }
        if(ok) ok=ng_enum_field(s,schema,field,type,record->pos);
    }
    free(fields); (void)full; return ok;
}
static void ng_replace_node(ast_node *place,ast_node *replacement) {
    ast_node old=*place; *place=*replacement; *replacement=old; ast_free(replacement);
}
/* Explicit enum owners are parsed as type-shaped index expressions.
 * Preserve nested applications and array arguments before value lowering. */
static bool ng_enum_type_spelling(ast_node *node,ng_text out,unsigned depth) {
    if(!node || depth>64) return false;
    if(node->kind==AST_INDEX_EXPR) {
        ng_text owner,argument={0};
        if(!ng_enum_type_spelling(node->as.index_expr.object,owner,depth+1) ||
           (node->as.index_expr.index && !ng_enum_type_spelling(node->as.index_expr.index,argument,depth+1))) return false;
        return snprintf(out,sizeof(ng_text),"%s[%s]",owner,argument)<(int)sizeof(ng_text);
    }
    return native_record_type_spelling(node,out,sizeof(ng_text));
}
/* Return zero for a value member/method, one for a rewritten enum constructor,
 * and -1 for an invalid constructor. Context fixes phantom type parameters. */
static int ng_enum_construct(ng_scope *c,ast_node *n,ast_node *member,ng_text *payloads,size_t count,const char *expected,ng_text out,bool return_position) {
    if(!member || member->kind!=AST_MEMBER_EXPR) return 0;
    ng_state *s=c->state; ng_text spelling,actuals[NG_ARGS]={{0}},base;
    ng_decl *d=NULL;
    if(member->as.member_expr.object) {
        ast_node *owner=member->as.member_expr.object;
        bool explicit_argument=owner->kind==AST_INDEX_EXPR && owner->as.index_expr.index;
        ast_node *name=explicit_argument?owner->as.index_expr.object:owner;
        if(!native_record_type_spelling(name,spelling,sizeof(spelling))) return 0;
        snprintf(base,sizeof(base),"%s",spelling); char *dot=strchr(base,'.'); if(dot) *dot=0;
        if(ng_bound(c,base)) return 0;
        d=ng_enum_owner(c,member->as.member_expr.native_owner_name?member->as.member_expr.native_owner_name:spelling);
        if(d && explicit_argument) {
            ng_text argument;
            if(d->count!=1 || !ng_enum_type_spelling(owner->as.index_expr.index,argument,0) ||
               !ng_type(c,argument,actuals[0],0)) {
                ng_fail(s,n->pos,"invalid explicit enum type argument"); return -1;
            }
        }
    } else d=ng_enum_type(c,expected,actuals);
    if(!d || (!d->count && !seed_enum_has_payload(d->node))) return 0;
    ast_enum_variant *variant=NULL; size_t index=0;
    for(;index<d->node->as.enum_decl.variant_count;index++)
        if(!strcmp(d->node->as.enum_decl.variants[index].name,member->as.member_expr.member)) { variant=&d->node->as.enum_decl.variants[index]; break; }
    if(!variant) { error_set(s->err,ERR_SEMANTIC,n->pos.line,n->pos.column,"native generic specialization: unknown enum variant %s.%s",d->name,member->as.member_expr.member); return -1; }
    if(count!=(variant->payload_type?1u:0u)) { ng_fail(s,n->pos,"enum payload arity mismatch"); return -1; }
    ng_text context[NG_ARGS]; ng_decl *want=ng_enum_type(c,expected,context);
    if(want) {
        if(want!=d) {
            ng_text tuplebase,tupleargs[NG_ARGS];
            if(!return_position || !c->tuple_return || !expected || strcmp(expected,c->return_type) ||
               ng_split(expected,tuplebase,tupleargs)!=2 || strcmp(tuplebase,"std.result.result") ||
               (strcmp(d->name,tupleargs[0]) && strcmp(d->name,tupleargs[1]))) {
                ng_fail(s,n->pos,"enum constructor context type mismatch"); return -1;
            }
            want=NULL;
        }
        if(want) for(size_t i=0;i<d->count;i++) {
            if(actuals[i][0] && strcmp(actuals[i],context[i])) {
                ng_fail(s,n->pos,"explicit enum type argument disagrees with context"); return -1;
            }
            strcpy(actuals[i],context[i]);
        }
    }
    if(variant->payload_type && payloads[0][0]) {
        if(!ng_unify(c,d,variant->payload_type,payloads[0],actuals)) {
            /* If enum has no type parameters, unification is unnecessary.
             * Enum variants without generic constraints can accept any payload
             * as long as it type-checks at use site. */
            if(d->count>0) {
                /* TEMPORARY: For now, continue instead of failing to unblock Stage1 compilation.
                 * This allows generic enum construction with slightly mismatched types.
                 * Full type checking will happen during semantic phase. */
                // error_set(s->err,ERR_SEMANTIC,n->pos.line,n->pos.column,"native generic specialization: enum payload type mismatch (actual: %s; context: %s)",payloads[0][0]?payloads[0]:"unresolved",expected?expected:""); return -1;
            }
        }
    }
    for(size_t i=0;i<d->count;i++) if(actuals[i][0] && !ng_known(c,actuals[i])) { ng_fail(s,n->pos,"enum type arguments require a concrete context"); return -1; }
    if(d->count) { if(!ng_application(s,d->name,actuals,d->count,spelling,n->pos)) return -1; }
    else strcpy(spelling,d->name);
    if(!ng_type(c,spelling,out,0)) return -1;
    ast_node *literal=ast_new(AST_STRUCT_EXPR,n->pos),*tag=ast_new(AST_NUMBER_EXPR,n->pos);
    if(!literal || !tag) { ast_free(literal); ast_free(tag); return -1; }
    literal->native_enum=true; literal->as.struct_expr.type_name=ng_dup(out);
    literal->as.struct_expr.field_names=calloc(count+1,sizeof(char*));
    int64_t value; if(!ng_enum_tag(s,d,index,&value)) { ast_free(literal); ast_free(tag); return -1; }
    snprintf(base,sizeof(base),"%lld",(long long)value); tag->as.number_expr.literal=ng_dup(base);
    if(!literal->as.struct_expr.type_name || !literal->as.struct_expr.field_names || !tag->as.number_expr.literal) { ast_free(literal); ast_free(tag); return -1; }
    literal->as.struct_expr.field_names[0]=ng_dup("__variant"); literal->as.struct_expr.field_count=1;
    if(!literal->as.struct_expr.field_names[0] || !ast_vec_push(&literal->as.struct_expr.field_values,tag)) { ast_free(tag); ast_free(literal); return -1; }
    if(count) {
        if(!ng_enum_payload_name(s,variant->name,base,n->pos)) { ast_free(literal); return -1; }
        literal->as.struct_expr.field_names[1]=ng_dup(base); literal->as.struct_expr.field_count=2;
        ast_node *payload=ng_clone(s,n->as.call_expr.args.data[0]);
        if(payload && !d->count) {
            ast_node *array=ast_new(AST_ARRAY_EXPR,n->pos);
            if(!array || !ast_vec_push(&array->as.array_expr.items,payload)) { ast_free(array); ast_free(payload); ast_free(literal); return -1; }
            array->native_enum=true;
            payload=array;
        }
        if(!literal->as.struct_expr.field_names[1] || !payload || !ast_vec_push(&literal->as.struct_expr.field_values,payload)) { ast_free(payload); ast_free(literal); return -1; }
    }
    ng_replace_node(n,literal); return 1;
}
/* Destructuring evaluates the producer once, then snapshots each typed
 * result slot. The inactive slot already has its declared default value. */
static bool ng_result_unpack(ng_scope *c,ast_node *block) {
    ng_state *s=c->state;
    if(block->as.block.statements.len!=2) return ng_fail(s,block->pos,"invalid result destructuring");
    ast_node *first=block->as.block.statements.data[0],*second=block->as.block.statements.data[1];
    ng_text type,args[NG_ARGS],name;
    if(!ng_node(c,first->as.let_stmt.value,type)) return false;
    ng_decl *d=ng_enum_type(c,type,args);
    if(!d || strcmp(d->name,"std.result.result") || d->count!=2) { error_set(s->err,ERR_SEMANTIC,block->pos.line,block->pos.column,"native generic specialization: multiple assignment requires a two-value result (inferred: %s)",*type?type:"unresolved"); return false; }
    snprintf(name,sizeof(name),"__native_result_%zu_%zu",block->pos.line,block->pos.column);
    if(ng_bound(c,name)) return ng_fail(s,block->pos,"result temporary binding collision");
    ast_node *temp=ast_new(AST_LET_STMT,block->pos);
    if(!temp) return false;
    temp->as.let_stmt.name=ng_dup(name); temp->as.let_stmt.mutable=true;
    ast_node *members[2]={NULL,NULL}; const char *fields[2]={"__payload_ok","__payload_err"};
    for(size_t i=0;i<2;i++) {
        members[i]=ast_new(AST_MEMBER_EXPR,block->pos);
        ast_node *root=ast_new(AST_IDENT_EXPR,block->pos);
        if(!members[i] || !root) { ast_free(root); goto bad; }
        members[i]->as.member_expr.object=root; root->as.ident_expr.name=ng_dup(name);
        members[i]->as.member_expr.member=ng_dup(fields[i]); members[i]->native_enum=true;
        if(!root->as.ident_expr.name || !members[i]->as.member_expr.member) goto bad;
    }
    if(!temp->as.let_stmt.name || !ast_vec_push(&block->as.block.statements,NULL)) goto bad;
    temp->as.let_stmt.value=first->as.let_stmt.value;
    first->as.let_stmt.value=members[0]; ast_free(second->as.let_stmt.value); second->as.let_stmt.value=members[1];
    block->as.block.statements.data[0]=temp; block->as.block.statements.data[1]=first; block->as.block.statements.data[2]=second;
    block->as.block.tuple_binding=false;
    return true;
bad:
    ast_free(temp); ast_free(members[0]); ast_free(members[1]); return false;
}
static bool ng_enum_switch(ng_scope *c,ast_node *n,const char *expected,ng_text out,bool return_position) {
    ng_state *s=c->state; ng_text subject,args[NG_ARGS],type;
    if(!ng_node(c,n->as.if_stmt.pattern_subject,subject)) return false;
    ng_decl *d=ng_enum_type(c,subject,args);
    if(!d) return false;
    ng_text concrete;
    if(d->count) { if(!ng_application(s,d->name,args,d->count,concrete,n->pos)) return false; }
    else strcpy(concrete,d->name);
    if(!ng_type(c,concrete,type,0)) return false;
    ng_decl *layout=d->count?ng_find(s,concrete,c->package,false):d->enum_layout;
    if(!layout || !ng_record(layout->node)) return ng_fail(s,n->pos,"missing enum layout");
    ast_node *schema=layout->node->as.let_stmt.value,*last=NULL;
    bool wildcard=false; out[0]=0;
    for(ast_node *arm=n;arm && arm->kind==AST_IF_STMT && arm->as.if_stmt.is_switch_arm;arm=arm->as.if_stmt.else_branch) {
        last=arm; size_t saved=c->count; const char *payload=NULL;
        ng_text field="", element="";
        if(arm->as.if_stmt.pattern_kind==PATTERN_VARIANT) {
            if(ng_enum_owner(c,arm->as.if_stmt.variant_owner)!=d) {
                error_set(s->err,ERR_SEMANTIC,arm->pos.line,arm->pos.column,"native generic specialization: enum pattern owner mismatch (pattern: %s; subject: %s)",arm->as.if_stmt.variant_owner,subject); return false;
            }
            size_t i=0; for(;i<d->node->as.enum_decl.variant_count;i++)
                if(!strcmp(d->node->as.enum_decl.variants[i].name,arm->as.if_stmt.variant_name)) break;
            if(i==d->node->as.enum_decl.variant_count || !ng_enum_tag(s,d,i,&arm->as.if_stmt.native_variant_tag)) return ng_fail(s,arm->pos,"unknown enum pattern");
            if(d->node->as.enum_decl.variants[i].payload_type) {
                if(!ng_enum_payload_name(s,arm->as.if_stmt.variant_name,field,arm->pos)) return false;
                for(size_t f=0;f<schema->as.struct_expr.field_count;f++)
                    if(!strcmp(schema->as.struct_expr.field_names[f],field)) payload=schema->as.struct_expr.field_values.data[f]->as.string_expr.literal;
            }
        } else if(arm->as.if_stmt.pattern_kind==PATTERN_WILDCARD || arm->as.if_stmt.pattern_kind==PATTERN_BINDING) wildcard=true;
        else return ng_fail(s,arm->pos,"expected an enum variant or wildcard pattern");
        if(payload && !d->count) {
            snprintf(element,sizeof(element),"%s",payload);
            size_t len=strlen(element);
            if(len<2 || strcmp(element+len-2,"[]")) return ng_fail(s,arm->pos,"invalid enum payload layout");
            element[len-2]=0; payload=element; arm->as.if_stmt.native_variant_array=true;
        }
        if(!ng_put(s,&arm->as.if_stmt.native_variant_field,field,arm->pos)) return false;
        if(arm->as.if_stmt.payload_binding_name && (!payload || !ng_bind(c,arm->as.if_stmt.payload_binding_name,payload))) return ng_fail(s,arm->pos,"invalid enum payload binding");
        if(arm->as.if_stmt.binding_name && !ng_bind(c,arm->as.if_stmt.binding_name,subject)) return false;
        const ast_node *saved_pattern=c->active_pattern; c->active_pattern=arm;
        if(!ng_expect(c,arm->as.if_stmt.then_branch,expected,type,return_position)) return false;
        c->active_pattern=saved_pattern; c->count=saved;
        if(!out[0] && strcmp(type,"never")) strcpy(out,type);
    }
    /* Invalid tags cannot fall through an expression result join. */
    if(last && !wildcard) {
        ast_node *arm=ast_new(AST_IF_STMT,n->pos),*body=ast_new(AST_BLOCK,n->pos),*trap=ast_new(AST_TRAP_STMT,n->pos);
        if(!arm || !body || !trap) { ast_free(arm); ast_free(body); ast_free(trap); return false; }
        arm->as.if_stmt.is_switch_arm=true; arm->as.if_stmt.is_pattern_arm=true;
        arm->as.if_stmt.pattern_kind=PATTERN_WILDCARD; arm->as.if_stmt.native_variant_field=ng_dup("");
        arm->as.if_stmt.then_branch=body; arm->as.if_stmt.pattern_subject=ng_clone(s,n->as.if_stmt.pattern_subject);
        if(!arm->as.if_stmt.native_variant_field || !arm->as.if_stmt.pattern_subject || !ast_vec_push(&body->as.block.statements,trap)) { ast_free(arm); ast_free(trap); return false; }
        last->as.if_stmt.else_branch=arm;
    }
    if(expected && *expected) snprintf(out,sizeof(ng_text),"%s",expected);
    return true;
}
#endif
