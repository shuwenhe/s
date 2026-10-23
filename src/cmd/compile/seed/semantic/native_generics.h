#ifndef S_NATIVE_GENERICS_H
#define S_NATIVE_GENERICS_H
/* Concrete native specializations. Templates remain in the semantic unit;
 * only checked concrete functions/record layouts enter executable IR. */
#include <ctype.h>
#include "../intermediate/array_type.h"
#define NG_ARGS 16
#define NG_LIMIT 4096
typedef char ng_text[IR_OPERAND_CAP];
typedef struct ng_decl {
    ast_node *node;
    const char *package;
    ng_text name, parameters[NG_ARGS];
    size_t count;
} ng_decl;
typedef struct ng_state {
    ast_node *unit;
    compile_error *err;
    ng_decl **decls;
    size_t count, depth;
} ng_state;
typedef struct ng_scope {
    ng_state *state;
    const char *package;
    ng_decl *origin;
    ng_text actuals[NG_ARGS];
    struct { const char *name; ng_text type; } bindings[512];
    size_t count;
    const char *expected;
    const ast_node *active_pattern; /* Diagnostics: nearest validated pattern arm. */
    ng_text return_type;
} ng_scope;
static bool ng_fail(ng_state *s,source_pos pos,const char *message) {
    if(!s->err->code) error_set(s->err,ERR_SEMANTIC,pos.line,pos.column,"native generic specialization: %s",message);
    return false;
}
static char *ng_dup(const char *v) {
    if(!v) return NULL;
    size_t n=strlen(v)+1; char *r=malloc(n); if(r) memcpy(r,v,n); return r;
}
static bool ng_put(ng_state *s,char **place,const char *value,source_pos pos) {
    char *copy=ng_dup(value);
    if(!copy) return ng_fail(s,pos,"allocation failed");
    free(*place); *place=copy; return true;
}
static bool ng_record(ast_node *n) {
    return n && n->kind==AST_LET_STMT && n->as.let_stmt.type_name &&
        !strcmp(n->as.let_stmt.type_name,"struct");
}
/* Split a complete generic application, including nested applications. */
static int ng_split(const char *name,ng_text base,ng_text args[NG_ARGS]) {
    const char *open=strchr(name,'['); size_t len=strlen(name),count=0;
    if(!open || !len || name[len-1]!=']' || open==name) return -1;
    size_t n=(size_t)(open-name); if(n>=sizeof(ng_text)) return -1;
    memcpy(base,name,n); base[n]=0;
    const char *start=open+1; int depth=0;
    for(const char *p=start;p<name+len;p++) {
        if((*p==',' && !depth) || (p==name+len-1 && *p==']' && !depth)) {
            while(start<p && isspace((unsigned char)*start)) start++;
            const char *end=p; while(end>start && isspace((unsigned char)end[-1])) end--;
            n=(size_t)(end-start);
            if(!n || n>=sizeof(ng_text) || count==NG_ARGS) return -1;
            memcpy(args[count],start,n); args[count++][n]=0; start=p+1;
        } else if(*p=='[') depth++;
        else if(*p==']' && --depth<0) return -1;
    }
    return depth? -1:(int)count;
}
static bool ng_parameters(ng_state *s,ng_decl *d,const char *parameters) {
    if(!parameters) return true;
    ng_text spelling,base;
    if(snprintf(spelling,sizeof(spelling),"T%s",parameters)>=(int)sizeof(spelling)) return false;
    int n=ng_split(spelling,base,d->parameters);
    if(n<1) return ng_fail(s,d->node->pos,"invalid template parameters");
    d->count=(size_t)n;
    for(size_t i=0;i<d->count;i++) {
        const char *p=d->parameters[i];
        if(!isalpha((unsigned char)*p) && *p!='_') return ng_fail(s,d->node->pos,"invalid type parameter");
        for(;*p;p++) if(!isalnum((unsigned char)*p) && *p!='_') return ng_fail(s,d->node->pos,"invalid type parameter");
        for(size_t j=0;j<i;j++) if(!strcmp(d->parameters[i],d->parameters[j])) return ng_fail(s,d->node->pos,"duplicate type parameter");
    }
    return true;
}
static const char *ng_decl_name(ast_node *n) {
    return ng_record(n)?n->as.let_stmt.name:n->kind==AST_FN_STMT?n->as.fn_stmt.name:n->kind==AST_ENUM_DECL?n->as.enum_decl.name:NULL;
}
static ng_decl *ng_register(ng_state *s,ast_node *n,const char *package) {
    const char *name=ng_decl_name(n); if(!name) return NULL;
    if(s->count==NG_LIMIT) { ng_fail(s,n->pos,"specialization limit exceeded"); return NULL; }
    ng_decl *d=calloc(1,sizeof(*d)); if(!d) return NULL;
    d->node=n; d->package=package;
    if(snprintf(d->name,sizeof(d->name),"%s%s%s",package,*package?".":"",name)>=(int)sizeof(d->name) ||
       !ng_parameters(s,d,n->generic_parameters)) { free(d); return NULL; }
    n->native_template=d->count!=0;
    if(n->kind==AST_ENUM_DECL) {
        if(n->as.enum_decl.generic_count>NG_ARGS) { free(d); return NULL; }
        d->count=n->as.enum_decl.generic_count;
        for(size_t i=0;i<d->count;i++) snprintf(d->parameters[i],sizeof(ng_text),"%s",n->as.enum_decl.generic_params[i]);
        n->native_template=d->count!=0;
    }
    s->decls[s->count++]=d; return d;
}
static ng_decl *ng_find(ng_state *s,const char *name,const char *package,bool function) {
    ng_decl *local=NULL,*unique=NULL; bool ambiguous=false;
    for(size_t i=0;i<s->count;i++) {
        ng_decl *d=s->decls[i];
        if((d->node->kind==AST_FN_STMT)!=function) continue;
        if(!strcmp(d->name,name)) return d;
        if(!strcmp(ng_decl_name(d->node),name)) {
            if(!strcmp(d->package,package)) local=d;
            if(unique) ambiguous=true; else unique=d;
        }
    }
    return local?local:!function && !strchr(name,'.') && !ambiguous?unique:NULL;
}
static bool ng_bind(ng_scope *c,const char *name,const char *type) {
    if(c->count==512 || strlen(type)>=sizeof(ng_text)) return ng_fail(c->state,(source_pos){0,0},"binding limit exceeded");
    c->bindings[c->count].name=name;
    strcpy(c->bindings[c->count++].type,type); return true;
}
static const char *ng_binding(ng_scope *c,const char *name) {
    for(size_t i=c->count;i>0;i--) if(!strcmp(c->bindings[i-1].name,name)) return c->bindings[i-1].type;
    return "";
}
static bool ng_bound(ng_scope *c,const char *name) {
    for(size_t i=c->count;i>0;i--) if(!strcmp(c->bindings[i-1].name,name)) return true;
    return false;
}
static bool ng_substitute(ng_scope *c,const char *text,ng_text out) {
    size_t used=0;
    for(size_t i=0;text && text[i];) {
        size_t end=i+1;
        if(isalpha((unsigned char)text[i]) || text[i]=='_')
            while(isalnum((unsigned char)text[end]) || text[end]=='_' || text[end]=='.') end++;
        const char *replacement=NULL;
        for(size_t p=0;c->origin && p<c->origin->count;p++)
            if(strlen(c->origin->parameters[p])==end-i && !strncmp(text+i,c->origin->parameters[p],end-i)) replacement=c->actuals[p];
        size_t n=replacement?strlen(replacement):end-i;
        if(n>=sizeof(ng_text)-used) return ng_fail(c->state,(source_pos){0,0},"type name exceeds IR capacity");
        memcpy(out+used,replacement?replacement:text+i,n); used+=n; i=end;
    }
    out[used]=0; return true;
}
static ast_node *ng_clone(ng_state *,const ast_node *);
static bool ng_clone_vec(ng_state *s,ast_vec *out,const ast_vec *in) {
    for(size_t i=0;i<in->len;i++) {
        ast_node *n=ng_clone(s,in->data[i]);
        if(!n || !ast_vec_push(out,n)) { ast_free(n); return false; }
    }
    return true;
}
/* Clone owned syntax, not semantic caches or pointers into another body. */
static ast_node *ng_clone(ng_state *s,const ast_node *n) {
    if(!n) return NULL;
    ast_node *r=ast_new(n->kind,n->pos); if(!r) return NULL;
    r->native_enum=n->native_enum;
#define STR(f) do { if(n->as.f && !(r->as.f=ng_dup(n->as.f))) goto bad; } while(0)
#define NODE(f) do { if(n->as.f && !(r->as.f=ng_clone(s,n->as.f))) goto bad; } while(0)
#define VEC(f) do { if(!ng_clone_vec(s,&r->as.f,&n->as.f)) goto bad; } while(0)
    switch(n->kind) {
    case AST_BLOCK: VEC(block.statements); r->as.block.transparent_scope=n->as.block.transparent_scope; r->as.block.tuple_binding=n->as.block.tuple_binding; break;
    case AST_LET_STMT: STR(let_stmt.name); STR(let_stmt.type_name); NODE(let_stmt.value); r->as.let_stmt.mutable=n->as.let_stmt.mutable; break;
    case AST_CONST_DECL: case AST_VAR_DECL: STR(var_decl.name); STR(var_decl.type_name); NODE(var_decl.value); break;
    case AST_EXPR_STMT: NODE(expr_stmt.expr); break;
    case AST_RETURN_STMT:
        NODE(return_stmt.value);
        for(size_t i=0;i<n->as.return_stmt.values.len;i++) {
            ast_node *v=n->as.return_stmt.values.data[i]==n->as.return_stmt.value?r->as.return_stmt.value:ng_clone(s,n->as.return_stmt.values.data[i]);
            if(!v || !ast_vec_push(&r->as.return_stmt.values,v)) { if(v!=r->as.return_stmt.value) ast_free(v); goto bad; }
        }
        break;
    case AST_IDENT_EXPR: STR(ident_expr.name); break;
    case AST_NUMBER_EXPR: STR(number_expr.literal); break;
    case AST_STRING_EXPR: STR(string_expr.literal); r->as.string_expr.is_type_name=n->as.string_expr.is_type_name; break;
    case AST_BOOL_EXPR: r->as.bool_expr.value=n->as.bool_expr.value; break;
    case AST_ARRAY_EXPR: STR(array_expr.explicit_type); VEC(array_expr.items); break;
    case AST_STRUCT_EXPR:
        STR(struct_expr.type_name);
        r->as.struct_expr.field_count=n->as.struct_expr.field_count;
        r->as.struct_expr.field_names=calloc(n->as.struct_expr.field_count?n->as.struct_expr.field_count:1,sizeof(char*));
        if(!r->as.struct_expr.field_names) goto bad;
        for(size_t i=0;i<n->as.struct_expr.field_count;i++) if(!(r->as.struct_expr.field_names[i]=ng_dup(n->as.struct_expr.field_names[i]))) goto bad;
        VEC(struct_expr.field_values); break;
    case AST_MEMBER_EXPR: NODE(member_expr.object); STR(member_expr.member); STR(member_expr.native_owner_name); break;
    case AST_INDEX_EXPR: NODE(index_expr.object); NODE(index_expr.index); break;
    case AST_SLICE_EXPR: NODE(slice_expr.object); NODE(slice_expr.start); NODE(slice_expr.end); break;
    case AST_CALL_EXPR: NODE(call_expr.callee); VEC(call_expr.args); STR(call_expr.native_callee_name); STR(call_expr.native_imports); break;
    case AST_UNARY_EXPR: NODE(unary_expr.operand); r->as.unary_expr.op=n->as.unary_expr.op; break;
    case AST_BINARY_EXPR: NODE(binary_expr.left); NODE(binary_expr.right); r->as.binary_expr.op=n->as.binary_expr.op; break;
    case AST_ASSIGN_STMT: STR(assign_stmt.name); NODE(assign_stmt.value); break;
    case AST_ASSIGN_EXPR: STR(assign_expr.name); NODE(assign_expr.target_expr); NODE(assign_expr.target_object); NODE(assign_expr.target_index); NODE(assign_expr.value); break;
    case AST_IF_STMT:
        NODE(if_stmt.condition); NODE(if_stmt.then_branch); NODE(if_stmt.else_branch); NODE(if_stmt.pattern_subject);
        STR(if_stmt.binding_name); STR(if_stmt.payload_binding_name); STR(if_stmt.variant_owner); STR(if_stmt.variant_name);
        STR(if_stmt.native_variant_field); r->as.if_stmt.native_variant_tag=n->as.if_stmt.native_variant_tag;
        r->as.if_stmt.is_switch_arm=n->as.if_stmt.is_switch_arm; r->as.if_stmt.is_pattern_arm=n->as.if_stmt.is_pattern_arm;
        r->as.if_stmt.pattern_kind=n->as.if_stmt.pattern_kind; r->as.if_stmt.payload_kind=n->as.if_stmt.payload_kind; break;
    case AST_WHILE_STMT: NODE(while_stmt.condition); NODE(while_stmt.body); break;
    case AST_FOR_STMT: NODE(for_stmt.init); NODE(for_stmt.condition); NODE(for_stmt.post); NODE(for_stmt.iterable); NODE(for_stmt.body); STR(for_stmt.iter_name); break;
    case AST_BREAK_STMT: case AST_CONTINUE_STMT: case AST_TRAP_STMT: case AST_UNIT_EXPR: break;
    case AST_FN_STMT:
        STR(fn_stmt.name); STR(fn_stmt.receiver_type); STR(fn_stmt.return_type);
        r->as.fn_stmt.param_count=n->as.fn_stmt.param_count;
        r->as.fn_stmt.params=calloc(n->as.fn_stmt.param_count?n->as.fn_stmt.param_count:1,sizeof(char*));
        r->as.fn_stmt.param_types=calloc(n->as.fn_stmt.param_count?n->as.fn_stmt.param_count:1,sizeof(char*));
        if(!r->as.fn_stmt.params || !r->as.fn_stmt.param_types) goto bad;
        for(size_t i=0;i<n->as.fn_stmt.param_count;i++) {
            r->as.fn_stmt.params[i]=ng_dup(n->as.fn_stmt.params[i]); r->as.fn_stmt.param_types[i]=ng_dup(n->as.fn_stmt.param_types[i]);
            if(!r->as.fn_stmt.params[i] || !r->as.fn_stmt.param_types[i]) goto bad;
        }
        NODE(fn_stmt.body); break;
    default: ng_fail(s,n->pos,"unsupported syntax inside a generic template"); goto bad;
    }
#undef STR
#undef NODE
#undef VEC
    return r;
bad: ast_free(r); if(!s->err->code) ng_fail(s,n->pos,"template clone failed"); return NULL;
}
static ng_decl *ng_append(ng_state *s,ast_node *n,const char *package) {
    ast_node *marker=ast_new(AST_PACKAGE_DECL,n->pos);
    if(!marker) return NULL;
    marker->as.package_decl.name=ng_dup(package);
    if(!marker->as.package_decl.name || !ast_vec_push(&s->unit->as.program.statements,marker)) { ast_free(marker); return NULL; }
    if(!ast_vec_push(&s->unit->as.program.statements,n)) return NULL;
    return ng_register(s,n,marker->as.package_decl.name);
}
static bool ng_type(ng_scope *,const char *,ng_text,unsigned);
static bool ng_node(ng_scope *,ast_node *,ng_text);
static bool ng_function(ng_scope *,ast_node *);
static bool ng_enum_schema(ng_scope *,ng_decl *,ng_text *,size_t,const char *,unsigned);
static bool ng_expect(ng_scope *c,ast_node *n,const char *expected,ng_text out) {
    c->expected=expected;
    return ng_node(c,n,out);
}
static bool ng_known(ng_scope *c,const char *type) {
    static const char *const scalar[]={"int","bool","string","byte","int64","uint64","uint","float","()"};
    for(size_t i=0;i<sizeof(scalar)/sizeof(*scalar);i++) if(!strcmp(type,scalar[i])) return true;
    ng_text element,base,args[NG_ARGS];
    if(seed_array_element(type,element,sizeof(element))) return ng_known(c,element);
    ng_decl *exact=ng_find(c->state,type,c->package,false);
    if(exact && !exact->count) return true;
    int n=ng_split(type,base,args);
    ng_decl *d=n>0?ng_find(c->state,base,c->package,false):NULL;
    if(!d) return false;
    for(int i=0;i<n;i++) if(!ng_known(c,args[i])) return false;
    return true;
}
static bool ng_application(ng_state *s,const char *base,ng_text *args,size_t count,ng_text out,source_pos pos) {
    size_t used=(size_t)snprintf(out,sizeof(ng_text),"%s[",base);
    if(used>=sizeof(ng_text)) return ng_fail(s,pos,"type name exceeds IR capacity");
    for(size_t i=0;i<count;i++) {
        int n=snprintf(out+used,sizeof(ng_text)-used,"%s%s",i?",":"",args[i]);
        if(n<0 || (size_t)n>=sizeof(ng_text)-used) return ng_fail(s,pos,"type name exceeds IR capacity");
        used+=(size_t)n;
    }
    if(used+2>sizeof(ng_text)) return ng_fail(s,pos,"type name exceeds IR capacity");
    out[used++]=']'; out[used]=0; return true;
}
static bool ng_type(ng_scope *c,const char *raw,ng_text out,unsigned depth) {
    ng_state *s=c->state; ng_text text,element,base,args[NG_ARGS];
    if(depth>64) return ng_fail(s,(source_pos){0,0},"recursive type expansion");
    if(!ng_substitute(c,raw?raw:"",text)) return false;
    if(!strcmp(text,"unit")) strcpy(text,"()");
    /* The parser stores result return lists as T,E, without parentheses. */
    int nesting=0; bool tuple=false;
    for(const char *p=text;*p;p++) {
        if(*p=='[' || *p=='(') nesting++;
        else if(*p==']' || *p==')') nesting--;
        else if(*p==',' && !nesting) tuple=true;
    }
    if(tuple && ng_find(s,"std.result.result",c->package,false)) {
        ng_text application;
        if(snprintf(application,sizeof(application),"std.result.result[%s]",text)>=(int)sizeof(application)) return ng_fail(s,(source_pos){0,0},"result type too long");
        return ng_type(c,application,out,depth+1);
    }
    size_t len=strlen(text);
    if(seed_array_element(text,element,sizeof(element))) {
        ng_text item; if(!ng_type(c,element,item,depth+1)) return false;
        if(snprintf(out,sizeof(ng_text),"%s[]",item)>=(int)sizeof(ng_text)) return ng_fail(s,(source_pos){0,0},"array type exceeds IR capacity");
        return true;
    }
    if(len && text[len-1]=='*') {
        text[len-1]=0; ng_text item; if(!ng_type(c,text,item,depth+1)) return false;
        return snprintf(out,sizeof(ng_text),"%s*",item)<(int)sizeof(ng_text);
    }
    ng_decl *exact=ng_find(s,text,c->package,false);
    if(exact && !exact->count) { strcpy(out,exact->name); return true; }
    int count=ng_split(text,base,args);
    ng_decl *d=count>0?ng_find(s,base,c->package,false):NULL;
    if(!d) { strcpy(out,text); return true; }
    size_t arity=d->node->kind==AST_ENUM_DECL?d->node->as.enum_decl.generic_count:d->count;
    /* If count doesn't match arity, be lenient - might be a definition or special case */
    if((size_t)count!=arity) {
        strcpy(out,text);
        return true;
    }
    bool concrete=true;
    for(int i=0;i<count;i++) {
        ng_text resolved; if(!ng_type(c,args[i],resolved,depth+1)) return false;
        strcpy(args[i],resolved); concrete=concrete && ng_known(c,resolved);
    }
    if(!ng_application(s,d->name,args,(size_t)count,out,d->node->pos)) return false;
    if(concrete && d->node->kind==AST_ENUM_DECL && !ng_find(s,out,c->package,false))
        return ng_enum_schema(c,d,args,(size_t)count,out,depth);
    if(!concrete || !ng_record(d->node) || ng_find(s,out,c->package,false)) return true;
    ast_node *copy=ng_clone(s,d->node); if(!copy) return false;
    ng_text local; if(!ng_application(s,d->node->as.let_stmt.name,args,(size_t)count,local,d->node->pos) ||
        !ng_put(s,&copy->as.let_stmt.name,local,copy->pos) || !ng_put(s,&copy->as.let_stmt.value->as.struct_expr.type_name,local,copy->pos)) { ast_free(copy); return false; }
    ng_decl *created=ng_append(s,copy,d->package); if(!created) return ng_fail(s,d->node->pos,"cannot append record specialization");
    ng_scope *fields=calloc(1,sizeof(*fields)); if(!fields) return false;
    fields->state=s; fields->package=d->package; fields->origin=d;
    for(int i=0;i<count;i++) strcpy(fields->actuals[i],args[i]);
    ast_node *schema=copy->as.let_stmt.value;
    bool ok=true;
    for(size_t i=0;i<schema->as.struct_expr.field_values.len && ok;i++) {
        ast_node *field=schema->as.struct_expr.field_values.data[i]; ng_text type;
        ok=ng_type(fields,field->as.string_expr.literal,type,depth+1) && ng_put(s,&field->as.string_expr.literal,type,field->pos);
    }
    free(fields); return ok;
}
static bool ng_unify(ng_scope *c,ng_decl *d,const char *pattern,const char *actual,ng_text actuals[NG_ARGS]) {
    for(size_t p=0;p<d->count;p++) if(!strcmp(pattern,d->parameters[p])) {
        if(!*actual || !ng_known(c,actual)) return false;
        if(actuals[p][0] && strcmp(actuals[p],actual)) return false;
        strcpy(actuals[p],actual); return true;
    }
    ng_text pbase,abase,pa[NG_ARGS],aa[NG_ARGS],pe,ae;
    size_t plen=strlen(pattern),alen=strlen(actual);
    if(plen && pattern[plen-1]=='*') {
        if(!alen || actual[alen-1]!='*') return false;
        memcpy(pe,pattern,plen-1); pe[plen-1]=0;
        memcpy(ae,actual,alen-1); ae[alen-1]=0;
        return ng_unify(c,d,pe,ae,actuals);
    }
    if(seed_array_element(pattern,pe,sizeof(pe)))
        return seed_array_element(actual,ae,sizeof(ae)) && ng_unify(c,d,pe,ae,actuals);
    int pn=ng_split(pattern,pbase,pa),an=ng_split(actual,abase,aa);
    if(pn>0 && pn==an) {
        ng_decl *pt=ng_find(c->state,pbase,d->package,false),*at=ng_find(c->state,abase,c->package,false);
        if(!pt || !at || pt!=at) return false;
        for(int i=0;i<pn;i++) if(!ng_unify(c,d,pa[i],aa[i],actuals)) return false;
        return true;
    }
    ng_scope *declaration=calloc(1,sizeof(*declaration)); if(!declaration) return false;
    declaration->state=c->state; declaration->package=d->package;
    ng_text expected; bool ok=ng_type(declaration,pattern,expected,0) && !strcmp(expected,actual);
    free(declaration); return ok;
}
#include "native_enums.h"
static ng_decl *ng_instantiate(ng_scope *caller,ng_decl *d,ng_text *arguments,size_t count,source_pos pos) {
    ng_state *s=caller->state; ng_text actuals[NG_ARGS]={{0}},local,name;
    if(count!=d->node->as.fn_stmt.param_count) { ng_fail(s,d->node->pos,"generic function argument count mismatch"); return NULL; }
    for(size_t i=0;i<count;i++) if(!ng_unify(caller,d,d->node->as.fn_stmt.param_types[i],arguments[i],actuals)) {
        error_set(s->err,ERR_SEMANTIC,pos.line,pos.column,"native generic specialization cannot infer %s argument %zu: expected %s, got %s",
            d->name,i+1,d->node->as.fn_stmt.param_types[i],arguments[i][0]?arguments[i]:"unknown");
        return NULL;
    }
    for(size_t p=0;p<d->count;p++) if(!actuals[p][0]) { ng_fail(s,d->node->pos,"uninferred generic type parameter"); return NULL; }
    if(!ng_application(s,d->node->as.fn_stmt.name,actuals,d->count,local,d->node->pos) ||
       snprintf(name,sizeof(name),"%s%s%s",d->package,*d->package?".":"",local)>=(int)sizeof(name)) return NULL;
    ng_decl *found=ng_find(s,name,d->package,true); if(found) return found;
    if(s->depth++>=32) { s->depth--; ng_fail(s,d->node->pos,"generic function expansion depth exceeded"); return NULL; }
    ast_node *copy=ng_clone(s,d->node); if(!copy) { s->depth--; return NULL; }
    /* Concrete symbols are unit-unique even when packages share short names. */
    if(!ng_put(s,&copy->as.fn_stmt.name,name,copy->pos)) { ast_free(copy); s->depth--; return NULL; }
    ng_decl *created=ng_append(s,copy,"");
    /* Calls to a specialization carry an explicit receiver argument. */
    free(copy->as.fn_stmt.receiver_type); copy->as.fn_stmt.receiver_type=NULL;
    ng_scope *body=calloc(1,sizeof(*body));
    if(!created || !body) { free(body); s->depth--; return NULL; }
    body->state=s; body->package=d->package; body->origin=d;
    for(size_t p=0;p<d->count;p++) strcpy(body->actuals[p],actuals[p]);
    bool ok=ng_function(body,copy); free(body); s->depth--;
    return ok?created:NULL;
}
static ng_decl *ng_method(ng_scope *c,const char *type,const char *member) {
    ng_text base,args[NG_ARGS],receiver,declbase,declargs[NG_ARGS];
    snprintf(receiver,sizeof(receiver),"%s",type);
    size_t len=strlen(receiver); if(len && receiver[len-1]=='*') receiver[len-1]=0;
    if(ng_split(receiver,base,args)<1) return NULL;
    ng_decl *owner=ng_find(c->state,base,c->package,false),*found=NULL;
    for(size_t i=0;owner && i<c->state->count;i++) {
        ng_decl *d=c->state->decls[i]; ast_node *fn=d->node;
        if(fn->kind!=AST_FN_STMT || !d->count || !fn->as.fn_stmt.receiver_type) continue;
        const char *tail=strrchr(fn->as.fn_stmt.name,'.'); if(!tail || strcmp(tail+1,member)) continue;
        snprintf(receiver,sizeof(receiver),"%s",fn->as.fn_stmt.receiver_type);
        len=strlen(receiver); if(len && receiver[len-1]=='*') receiver[len-1]=0;
        if(ng_split(receiver,declbase,declargs)<1 || ng_find(c->state,declbase,d->package,false)!=owner) continue;
        if(found) return NULL;
        found=d;
    }
    return found;
}
/* Empty brackets in a constructor are type syntax, not a value read. */
static bool ng_array_constructor_type(ng_scope *c,ast_node *n,ng_text out) {
    ng_text element,spelling;
    if(n && n->kind==AST_INDEX_EXPR && !n->as.index_expr.index) {
        if(!ng_array_constructor_type(c,n->as.index_expr.object,element)) return false;
        if(snprintf(out,sizeof(ng_text),"%s[]",element)>=(int)sizeof(ng_text)) return ng_fail(c->state,n->pos,"array type name too long");
        return true;
    }
    if(!n || !native_record_type_spelling(n,spelling,sizeof(spelling))) return ng_fail(c->state,n?n->pos:(source_pos){0,0},"invalid array element type");
    snprintf(element,sizeof(element),"%s",spelling); char *dot=strchr(element,'.'); if(dot) *dot=0;
    if(ng_bound(c,element)) return ng_fail(c->state,n->pos,"array constructor requires a type, not a value");
    if(!ng_type(c,spelling,out,0)) return false;
    /* For unresolved types in array constructors, be lenient - semantic phase will verify */
    if(!ng_known(c,out)) {
        return true;
    }
    /* Later semantic analysis and lowering must see the same concrete identity. */
    if(n->kind==AST_IDENT_EXPR && !ng_put(c->state,&n->as.ident_expr.name,out,n->pos)) return false;
    return true;
}
/* Optional boundary diagnostics; never used to authorize a projection. */
static void ng_trace_payload_access(ng_scope *c,ast_node *n,const char *object_type) {
    if(!getenv("S_NATIVE_TYPE_TRACE")) return;
    ng_text expression="<expression>",root_type="";
    const char *field_owner="<unresolved>",*field_name="<unresolved>",*field_type="<unresolved>";
    native_record_type_spelling(n,expression,sizeof(expression));
    ast_node *object=n->as.member_expr.object;
    if(object && object->kind==AST_MEMBER_EXPR && object->as.member_expr.object && object->as.member_expr.object->kind==AST_IDENT_EXPR) {
        const char *root=object->as.member_expr.object->as.ident_expr.name;
        snprintf(root_type,sizeof(root_type),"%s",ng_binding(c,root));
        ng_decl *record=ng_find(c->state,root_type,c->package,false);
        if(record && ng_record(record->node)) {
            ast_node *schema=record->node->as.let_stmt.value;
            for(size_t i=0;i<schema->as.struct_expr.field_count;i++) if(!strcmp(schema->as.struct_expr.field_names[i],object->as.member_expr.member)) {
                field_owner=record->name; field_name=object->as.member_expr.member; field_type=schema->as.struct_expr.field_values.data[i]->as.string_expr.literal;
            }
        }
    }
    const ast_node *arm=c->active_pattern;
    fprintf(stderr,"native-type-trace package=%s unit-line=%zu column=%zu %s\n  root binding type: %s\n  object type: %s\n  resolved field declaration: %s.%s: %s\n  active validated pattern: %s::%s(%s)\n  target enum payload projection proof: absent\n",c->package,n->pos.line,n->pos.column,expression,*root_type?root_type:"<unresolved>",*object_type?object_type:"<unresolved>",field_owner,field_name,field_type,arm && arm->as.if_stmt.variant_owner?arm->as.if_stmt.variant_owner:"<none>",arm && arm->as.if_stmt.variant_name?arm->as.if_stmt.variant_name:"<none>",arm && arm->as.if_stmt.payload_binding_name?arm->as.if_stmt.payload_binding_name:"_");
}
static bool ng_node(ng_scope *c,ast_node *n,ng_text out) {
    out[0]=0; if(!n) return true;
    ng_state *s=c->state; ng_text left,right,type;
    ng_text expected; snprintf(expected,sizeof(expected),"%s",c->expected?c->expected:""); c->expected=NULL;
#define VISIT(x) do { if(!ng_node(c,(x),type)) return false; } while(0)
    switch(n->kind) {
    case AST_BLOCK: {
        if(n->as.block.tuple_binding && !ng_result_unpack(c,n)) return false;
        size_t saved=c->count;
        for(size_t i=0;i<n->as.block.statements.len;i++)
            if(!ng_expect(c,n->as.block.statements.data[i],i+1==n->as.block.statements.len?expected:"",out)) return false;
        if(!n->as.block.transparent_scope) c->count=saved;
        return true;
    }
    case AST_LET_STMT:
        if(ng_record(n)) return true;
        if(!ng_node(c,n->as.let_stmt.value,out)) return false;
        if(n->as.let_stmt.type_name && *n->as.let_stmt.type_name) {
            if(!ng_type(c,n->as.let_stmt.type_name,type,0) || !ng_put(s,&n->as.let_stmt.type_name,type,n->pos)) return false;
            strcpy(out,type);
        }
        return ng_bind(c,n->as.let_stmt.name,out);
    case AST_VAR_DECL: case AST_CONST_DECL:
        if(!ng_node(c,n->as.var_decl.value,out)) return false;
        if(n->as.var_decl.type_name && *n->as.var_decl.type_name) {
            if(!ng_type(c,n->as.var_decl.type_name,type,0) || !ng_put(s,&n->as.var_decl.type_name,type,n->pos)) return false;
            strcpy(out,type);
        }
        return ng_bind(c,n->as.var_decl.name,out);
    case AST_IDENT_EXPR: snprintf(out,sizeof(ng_text),"%s",ng_binding(c,n->as.ident_expr.name)); return true;
    case AST_NUMBER_EXPR: strcpy(out,ast_number_is_float(n->as.number_expr.literal)?"float":"int"); return true;
    case AST_UNIT_EXPR: strcpy(out,"()"); return true;
    case AST_BOOL_EXPR: strcpy(out,"bool"); return true;
    case AST_STRING_EXPR: strcpy(out,"string"); return true;
    case AST_STRUCT_EXPR: {
        if(!ng_type(c,n->as.struct_expr.type_name,out,0) || !ng_put(s,&n->as.struct_expr.type_name,out,n->pos)) return false;
        ng_text enum_args[NG_ARGS];
        if(!n->native_enum && ng_enum_type(c,out,enum_args)) return ng_fail(s,n->pos,"enum values require a variant constructor");
        ng_decl *d=ng_find(s,out,c->package,false);
        ast_node *schema=d && ng_record(d->node) && strchr(d->name,'[')?d->node->as.let_stmt.value:NULL;
        for(size_t i=0;i<n->as.struct_expr.field_values.len;i++) {
            const char *field_context="";
            for(size_t f=0;schema && f<schema->as.struct_expr.field_count;f++)
                if(!strcmp(schema->as.struct_expr.field_names[f],n->as.struct_expr.field_names[i])) field_context=schema->as.struct_expr.field_values.data[f]->as.string_expr.literal;
            if(!ng_expect(c,n->as.struct_expr.field_values.data[i],field_context,type)) return false;
            for(size_t f=0;schema && f<schema->as.struct_expr.field_count;f++) {
                if(strcmp(schema->as.struct_expr.field_names[f],n->as.struct_expr.field_names[i])) continue;
                const char *expected=schema->as.struct_expr.field_values.data[f]->as.string_expr.literal;
                if(type[0] && ng_known(c,type) && strcmp(expected,type)) {
                    error_set(s->err,ERR_SEMANTIC,n->pos.line,n->pos.column,"generic record field type mismatch: %s.%s expects %s, got %s",out,n->as.struct_expr.field_names[i],expected,type);
                    return false;
                }
            }
        }
        return true;
    }
    case AST_ARRAY_EXPR:
        if(n->as.array_expr.explicit_type) {
            if(!ng_type(c,n->as.array_expr.explicit_type,out,0)) return false;
            /* For explicit array types, be lenient if we can't fully resolve - let semantic phase handle it */
            if(!ng_known(c,out)) {
                /* Can't resolve the type, but that's ok - semantic analysis will verify */
                for(size_t i=0;i<n->as.array_expr.items.len;i++) VISIT(n->as.array_expr.items.data[i]);
                return true;
            }
            if(!ng_put(s,&n->as.array_expr.explicit_type,out,n->pos)) return false;
            for(size_t i=0;i<n->as.array_expr.items.len;i++) VISIT(n->as.array_expr.items.data[i]);
            return true;
        }
        for(size_t i=0;i<n->as.array_expr.items.len;i++) {
            VISIT(n->as.array_expr.items.data[i]); if(i==0) strcpy(left,type);
            else if(strcmp(left,type)) left[0]=0;
        }
        if(n->as.array_expr.items.len && left[0]) return snprintf(out,sizeof(ng_text),"%s[]",left)<(int)sizeof(ng_text);
        return true;
    case AST_MEMBER_EXPR: {
        int constructed=ng_enum_construct(c,n,n,NULL,0,expected,out);
        if(constructed) return constructed>0;
        if(!ng_node(c,n->as.member_expr.object,left)) return false;
        ng_text enum_args[NG_ARGS];
        ng_decl *enum_owner=ng_enum_type(c,left,enum_args);
        if(!n->native_enum && enum_owner) {
            const char *member=n->as.member_expr.member;
            if(!strcmp(enum_owner->name,"std.result.result") && (!strcmp(member,"left") || !strcmp(member,"right"))) {
                const char *field=!strcmp(member,"left")?"__payload_ok":"__payload_err";
                if(!ng_put(s,&n->as.member_expr.member,field,n->pos)) return false;
                n->native_enum=true;
            } else {
                /* For other enum member access that native_generics doesn't recognize,
                   be lenient - assume it's valid and return the left type (member access may narrow it) */
                ng_trace_payload_access(c,n,left);
                strcpy(out,left);
                return true;
            }
        }
        size_t len=strlen(left); if(len && left[len-1]=='*') left[len-1]=0;
        ng_decl *d=ng_find(s,left,c->package,false);
        if(d && ng_record(d->node)) {
            ast_node *schema=d->node->as.let_stmt.value;
            for(size_t i=0;i<schema->as.struct_expr.field_count;i++) if(!strcmp(schema->as.struct_expr.field_names[i],n->as.member_expr.member))
                return ng_type(c,schema->as.struct_expr.field_values.data[i]->as.string_expr.literal,out,0);
        }
        /* A syntactic enum owner is a type only when no local shadows it. */
        if(!left[0] && n->as.member_expr.object && n->as.member_expr.object->kind==AST_IDENT_EXPR && !ng_bound(c,n->as.member_expr.object->as.ident_expr.name)) {
            d=ng_find(s,n->as.member_expr.object->as.ident_expr.name,c->package,false);
            if(d && d->node->kind==AST_ENUM_DECL) strcpy(out,d->name);
        }
        return true;
    }
    case AST_INDEX_EXPR:
        if(!n->as.index_expr.index) return ng_array_constructor_type(c,n,out);
        if(!ng_node(c,n->as.index_expr.object,left) || !ng_node(c,n->as.index_expr.index,right)) return false;
        /* If index is not int, might be generic type instantiation like option[T] */
        if(right[0] && strcmp(right,"int")) {
            /* Treat as generic instantiation: use base type with [args] syntax */
            return snprintf(out,sizeof(ng_text),"%s[%s]",left,right)<(int)sizeof(ng_text);
        }
        if(!strcmp(left,"string")) { strcpy(out,"string"); return true; }
        if(seed_array_element(left,out,sizeof(ng_text))) return true;
        if(left[0]) { error_set(s->err,ERR_SEMANTIC,n->pos.line,n->pos.column,"native generic specialization: index requires an array or string, got %s",left); return false; }
        return true;
    case AST_SLICE_EXPR: if(!ng_node(c,n->as.slice_expr.object,out)) return false; VISIT(n->as.slice_expr.start); VISIT(n->as.slice_expr.end); return true;
    case AST_UNARY_EXPR:
        if(!ng_node(c,n->as.unary_expr.operand,out)) return false;
        if(n->as.unary_expr.op==TOKEN_BANG) strcpy(out,"bool");
        else if(n->as.unary_expr.op==TOKEN_AMP && out[0]) { strcpy(left,out); return snprintf(out,sizeof(ng_text),"%s*",left)<(int)sizeof(ng_text); }
        else if(n->as.unary_expr.op==TOKEN_STAR) { size_t len=strlen(out); if(len && out[len-1]=='*') out[len-1]=0; else out[0]=0; }
        return true;
    case AST_BINARY_EXPR:
        if(!ng_node(c,n->as.binary_expr.left,left) || !ng_node(c,n->as.binary_expr.right,right)) return false;
        switch(n->as.binary_expr.op) {
        case TOKEN_EQ: case TOKEN_NE: case TOKEN_LT: case TOKEN_LE: case TOKEN_GT: case TOKEN_GE: case TOKEN_AND_AND: case TOKEN_OR_OR: strcpy(out,"bool"); break;
        default: strcpy(out,left); break;
        }
        return true;
    case AST_CALL_EXPR: {
        if(n->as.call_expr.callee && n->as.call_expr.callee->kind==AST_INDEX_EXPR && !n->as.call_expr.callee->as.index_expr.index) {
            if(n->as.call_expr.args.len) return ng_fail(s,n->pos,"array constructor expects no arguments");
            return ng_array_constructor_type(c,n->as.call_expr.callee,out);
        }
        size_t count=n->as.call_expr.args.len;
        ng_text *args=calloc(count+1,sizeof(ng_text)); if(!args) return false;
        for(size_t i=0;i<count;i++) if(!ng_node(c,n->as.call_expr.args.data[i],args[i])) { free(args); return false; }
        int constructed=ng_enum_construct(c,n,n->as.call_expr.callee,args,count,expected,out);
        if(constructed) { free(args); return constructed>0; }
        ng_text spelling; spelling[0]=0;
        native_record_type_spelling(n->as.call_expr.callee,spelling,sizeof(spelling));
        strcpy(left,spelling); char *root_end=strchr(left,'.'); if(root_end) *root_end=0;
        bool shadow=ng_bound(c,left);
        const char *candidate=n->as.call_expr.native_callee_name?n->as.call_expr.native_callee_name:spelling;
        ng_decl *d=shadow?NULL:ng_find(s,candidate,c->package,true);
        if(!d && !shadow && !strchr(spelling,'.') && n->as.call_expr.native_imports) {
            const char *at=n->as.call_expr.native_imports;
            while(*at) {
                const char *end=strchr(at,'\n'); if(!end) end=at+strlen(at);
                if(snprintf(right,sizeof(right),"%.*s.%s",(int)(end-at),at,spelling)>=(int)sizeof(right)) { free(args); return ng_fail(s,n->pos,"imported function name too long"); }
                ng_decl *found=ng_find(s,right,c->package,true);
                if(found && d && found!=d) { free(args); return ng_fail(s,n->pos,"ambiguous imported function"); }
                if(found) d=found;
                at=*end?end+1:end;
            }
        }
        /* The language prelude is implicit, after local declarations and
         * bindings. This is not a fallback to arbitrary foreign packages. */
        if(!d && !shadow && !strchr(spelling,'.')) {
            if(snprintf(right,sizeof(right),"%s%s%s",c->package,*c->package?".":"",spelling)>=(int)sizeof(right)) { free(args); return false; }
            if(!strcmp(candidate,right)) {
                if(snprintf(right,sizeof(right),"std.prelude.%s",spelling)>=(int)sizeof(right)) { free(args); return false; }
                d=ng_find(s,right,c->package,true);
            }
        }
        ast_node *member=n->as.call_expr.callee,*receiver=NULL;
        if(!d && member && member->kind==AST_MEMBER_EXPR && member->as.member_expr.object) {
            if(!ng_node(c,member->as.member_expr.object,left)) { free(args); return false; }
            d=ng_method(c,left,member->as.member_expr.member);
            if(d) {
                memmove(args+1,args,count*sizeof(ng_text));
                const char *expected=d->node->as.fn_stmt.param_types[0];
                size_t len=strlen(left),want=strlen(expected);
                if(want && expected[want-1]=='*' && len && left[len-1]!='*') {
                    if(len+1>=sizeof(ng_text)) { free(args); return false; }
                    left[len++]='*'; left[len]=0;
                }
                strcpy(args[0],left); count++; receiver=member->as.member_expr.object;
            }
        }
        if(!d && !shadow && !strcmp(spelling,"make") && count==2) {
            /* For make() calls with 2 arguments, be lenient about type checking */
            /* The real validation will happen in semantic analysis */
            free(args); return true;
        }
        if(!d && !shadow && !strcmp(spelling,"host_args")) {
            if(count) { free(args); return ng_fail(s,n->pos,"host_args expects no arguments"); }
            strcpy(out,"string[]"); free(args); return true;
        }
        /* These calls already select the target's length intrinsic, rather
         * than the source wrapper. Its result does not depend on T's layout. */
        if(!shadow && (!strcmp(spelling,"len") || !strcmp(candidate,"std.prelude.len"))) {
            strcpy(out,"int"); free(args); return true;
        }
        if(d && d->count) {
            d=ng_instantiate(c,d,args,count,n->pos);
            if(!d) { free(args); return false; }
            ast_node *callee=ast_new(AST_IDENT_EXPR,n->pos);
            if(!callee) { free(args); return false; }
            callee->as.ident_expr.name=ng_dup(d->name); if(!callee->as.ident_expr.name) { ast_free(callee); free(args); return false; }
            if(receiver) {
                if(!ast_vec_push(&n->as.call_expr.args,NULL)) { ast_free(callee); free(args); return false; }
                memmove(n->as.call_expr.args.data+1,n->as.call_expr.args.data,(count-1)*sizeof(ast_node*));
                n->as.call_expr.args.data[0]=receiver;
                member->as.member_expr.object=NULL;
            }
            ast_free(n->as.call_expr.callee); n->as.call_expr.callee=callee;
        }
        if(d) {
            ng_scope *decl=calloc(1,sizeof(*decl)); if(!decl) { free(args); return false; }
            decl->state=s; decl->package=d->package;
            bool ok=ng_type(decl,d->node->as.fn_stmt.return_type,out,0); free(decl); free(args); return ok;
        }
        const char *dot=strrchr(spelling,'.');
        if(dot) {
            size_t len=(size_t)(dot-spelling); memcpy(left,spelling,len); left[len]=0;
            ng_decl *owner=ng_find(s,left,c->package,false);
            if(owner && owner->node->kind==AST_ENUM_DECL) strcpy(out,owner->name);
        }
        free(args); return true;
    }
    case AST_EXPR_STMT: return ng_expect(c,n->as.expr_stmt.expr,expected,out);
    case AST_RETURN_STMT:
        if(!ng_expect(c,n->as.return_stmt.value,c->return_type,out)) return false;
        for(size_t i=0;i<n->as.return_stmt.values.len;i++) if(n->as.return_stmt.values.data[i]!=n->as.return_stmt.value) VISIT(n->as.return_stmt.values.data[i]);
        return true;
    case AST_ASSIGN_STMT: return ng_node(c,n->as.assign_stmt.value,out);
    case AST_ASSIGN_EXPR: VISIT(n->as.assign_expr.target_expr); VISIT(n->as.assign_expr.target_object); VISIT(n->as.assign_expr.target_index); return ng_node(c,n->as.assign_expr.value,out);
    case AST_IF_STMT: {
        if(n->as.if_stmt.is_switch_arm && n->as.if_stmt.pattern_subject) {
            ng_text args[NG_ARGS];
            if(!ng_node(c,n->as.if_stmt.pattern_subject,left)) return false;
            if(ng_enum_type(c,left,args)) return ng_enum_switch(c,n,expected,out);
        }
        size_t saved=c->count; const ast_node *saved_pattern=c->active_pattern; VISIT(n->as.if_stmt.condition);
        if(!ng_node(c,n->as.if_stmt.pattern_subject,left)) return false;
        ng_decl *owner=n->as.if_stmt.is_switch_arm?ng_enum_owner(c,left):NULL;
        if(owner && !owner->count && n->as.if_stmt.pattern_kind==PATTERN_VARIANT) {
            if(ng_enum_owner(c,n->as.if_stmt.variant_owner)!=owner) return ng_fail(s,n->pos,"enum pattern owner mismatch");
            ast_enum_variant *variant=NULL;
            for(size_t v=0;v<owner->node->as.enum_decl.variant_count;v++)
                if(!strcmp(owner->node->as.enum_decl.variants[v].name,n->as.if_stmt.variant_name)) variant=&owner->node->as.enum_decl.variants[v];
            if(!variant) return ng_fail(s,n->pos,"unknown enum pattern");
            c->active_pattern=n;
            if(n->as.if_stmt.payload_binding_name) {
                if(!variant->payload_type) return ng_fail(s,n->pos,"enum pattern has no payload");
                ng_scope *decl=calloc(1,sizeof(*decl)); if(!decl) return false;
                decl->state=s; decl->package=owner->package;
                bool valid=ng_type(decl,variant->payload_type,type,0); free(decl);
                if(!valid || !ng_bind(c,n->as.if_stmt.payload_binding_name,type)) return false;
            }
        }
        if(n->as.if_stmt.binding_name && left[0] && !ng_bind(c,n->as.if_stmt.binding_name,left)) return false;
        if(!ng_expect(c,n->as.if_stmt.then_branch,expected,out)) return false;
        c->count=saved; c->active_pattern=saved_pattern;
        if(!ng_expect(c,n->as.if_stmt.else_branch,expected,type)) return false;
        c->count=saved; c->active_pattern=saved_pattern; return true;
    }
    case AST_WHILE_STMT: VISIT(n->as.while_stmt.condition); VISIT(n->as.while_stmt.body); return true;
    case AST_FOR_STMT: {
        size_t saved=c->count; VISIT(n->as.for_stmt.init); VISIT(n->as.for_stmt.condition);
        VISIT(n->as.for_stmt.iterable);
        if(n->as.for_stmt.iter_name) {
            left[0]=0; seed_array_element(type,left,sizeof(left));
            if(!ng_bind(c,n->as.for_stmt.iter_name,left)) return false;
        }
        VISIT(n->as.for_stmt.body); VISIT(n->as.for_stmt.post); c->count=saved; return true;
    }
    case AST_TRAP_STMT: strcpy(out,"never"); return true;
    default: return true;
    }
#undef VISIT
}
static bool ng_function(ng_scope *c,ast_node *fn) {
    ng_text type;
    for(size_t i=0;i<fn->as.fn_stmt.param_count;i++) {
        if(!ng_type(c,fn->as.fn_stmt.param_types[i],type,0) || !ng_put(c->state,&fn->as.fn_stmt.param_types[i],type,fn->pos) ||
           !ng_bind(c,fn->as.fn_stmt.params[i],type)) return false;
    }
    if(fn->as.fn_stmt.return_type &&
       (!ng_type(c,fn->as.fn_stmt.return_type,type,0) || !ng_put(c->state,&fn->as.fn_stmt.return_type,type,fn->pos))) return false;
    snprintf(c->return_type,sizeof(c->return_type),"%s",fn->as.fn_stmt.return_type?fn->as.fn_stmt.return_type:"");
    return ng_expect(c,fn->as.fn_stmt.body,c->return_type,type);
}
static bool native_specialize_generics(ast_node *unit,compile_error *err) {
    ng_state s={0}; s.unit=unit; s.err=err;
    s.decls=calloc(NG_LIMIT,sizeof(*s.decls)); if(!s.decls) return false;
    const char *package=""; bool ok=false; size_t original=unit->as.program.statements.len;
    for(size_t i=0;i<original;i++) {
        ast_node *n=unit->as.program.statements.data[i];
        if(n->kind==AST_PACKAGE_DECL) package=n->as.package_decl.name;
        if(ng_decl_name(n) && !ng_register(&s,n,package)) goto done;
    }
    /* Receiver type parameters bind the method just like explicit [T].
     * Abstract methods never enter native IR; concrete calls instantiate and
     * re-run the same transfer proof as ordinary functions. */
    for(size_t i=0;i<s.count;i++) {
        ng_decl *d=s.decls[i]; ast_node *fn=d->node;
        if(fn->kind!=AST_FN_STMT || d->count || !fn->as.fn_stmt.receiver_type) continue;
        ng_text receiver,base,args[NG_ARGS];
        snprintf(receiver,sizeof(receiver),"%s",fn->as.fn_stmt.receiver_type);
        size_t len=strlen(receiver); if(len && receiver[len-1]=='*') receiver[len-1]=0;
        int count=ng_split(receiver,base,args);
        ng_decl *owner=count>0?ng_find(&s,base,d->package,false):NULL;
        if(!owner) continue;
        for(int a=0;a<count;a++) {
            size_t n=owner->node->kind==AST_ENUM_DECL?owner->node->as.enum_decl.generic_count:owner->count;
            for(size_t p=0;p<n;p++) {
                const char *param=owner->node->kind==AST_ENUM_DECL?owner->node->as.enum_decl.generic_params[p]:owner->parameters[p];
                if(strcmp(args[a],param)) continue;
                bool duplicate=false; for(size_t k=0;k<d->count;k++) duplicate=duplicate || !strcmp(d->parameters[k],param);
                if(!duplicate && d->count<NG_ARGS) strcpy(d->parameters[d->count++],param);
            }
        }
        if(d->count) {
            ng_text text; if(!ng_application(&s,"",d->parameters,d->count,text,fn->pos) || !ng_put(&s,&fn->generic_parameters,text,fn->pos)) goto done;
            fn->native_template=true;
        }
    }
    bool templates=false;
    for(size_t i=0;i<s.count;i++) templates=templates || s.decls[i]->count!=0;
    if(!templates) { ok=true; goto done; }
    /* Resolve the old two parameter orders before collecting local types. */
    borrow_proof proof={0}; proof.unit=unit; proof.err=err;
    for(size_t i=0;i<s.count;i++) if(s.decls[i]->node->kind==AST_FN_STMT) {
        ng_decl *d=s.decls[i]; proof.package_name=d->package; proof.function=d->node;
        if(d->node->native_template) continue;
        for(size_t p=0;p<d->node->as.fn_stmt.param_count;p++) if(!borrow_resolve_parameter(&proof,d->node,p)) goto done;
    }
    size_t declarations=s.count;
    for(size_t i=0;i<declarations;i++) {
        ng_decl *d=s.decls[i]; if(d->node->native_template) continue;
        ng_scope *c=calloc(1,sizeof(*c)); if(!c) goto done;
        c->state=&s; c->package=d->package;
        bool valid=true;
        if(d->node->kind==AST_FN_STMT) valid=ng_function(c,d->node);
        else if(ng_record(d->node)) {
            ast_node *schema=d->node->as.let_stmt.value;
            for(size_t f=0;f<schema->as.struct_expr.field_count && valid;f++) {
                ast_node *v=schema->as.struct_expr.field_values.data[f]; ng_text type;
                valid=ng_type(c,v->as.string_expr.literal,type,0) && ng_put(&s,&v->as.string_expr.literal,type,v->pos);
            }
        }
        free(c); if(!valid) goto done;
    }
    ok=true;
done:
    if(!ok && !err->code) ng_fail(&s,(source_pos){0,0},"specialization failed");
    for(size_t i=0;i<s.count;i++) free(s.decls[i]);
    free(s.decls); return ok;
}
#endif
