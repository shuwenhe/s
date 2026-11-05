#ifndef S_TEMPLATE_FIELDS_H
#define S_TEMPLATE_FIELDS_H
/* Resolve dependent record fields symbolically during definition checking.
 * Concrete schemas still take precedence; this never aliases record identities. */
typedef struct template_type_span { const char *text; size_t length; } template_type_span;
static int template_type_arguments(const char *text, template_type_span *base,
        template_type_span args[16]) {
    const char *open=strchr(text,'['); size_t length=strlen(text);
    if(!open || !length || text[length-1]!=']') return 0;
    base->text=text; base->length=(size_t)(open-text);
    const char *start=open+1; unsigned depth=0; int count=0;
    for(const char *p=start;p<text+length;p++) {
        if((*p==',' && !depth) || (p==text+length-1 && *p==']' && !depth)) {
            const char *end=p;
            while(start<end && isspace((unsigned char)*start)) start++;
            while(end>start && isspace((unsigned char)end[-1])) end--;
            if(start==end || count==16) return 0;
            args[count++]=(template_type_span){start,(size_t)(end-start)}; start=p+1;
        } else if(*p=='[') depth++;
        else if(*p==']') { if(!depth) return 0; depth--; }
    }
    return depth?0:count;
}
static int template_span_equal(template_type_span span,const char *text) {
    return strlen(text)==span.length && !strncmp(span.text,text,span.length);
}
static int template_owned_nominal(semantic_ctx *ctx,const char *package,template_type_span token) {
    const char *current="";
    for(size_t i=0;i<ctx->root->as.program.statements.len;i++) {
        ast_node *decl=ctx->root->as.program.statements.data[i];
        if(decl->kind==AST_PACKAGE_DECL) current=decl->as.package_decl.name;
        if(strcmp(current,package)) continue;
        const char *name=NULL;
        if(decl->kind==AST_ENUM_DECL) name=decl->as.enum_decl.name;
        if(decl->kind==AST_LET_STMT && decl->as.let_stmt.type_name && !strcmp(decl->as.let_stmt.type_name,"struct")) name=decl->as.let_stmt.name;
        if(name && template_span_equal(token,name)) return 1;
    }
    return 0;
}
static const char *template_record_field_type(semantic_ctx *ctx,const char *type,
        const char *member) {
    template_type_span base,args[16],parameters[16],ignored;
    int count=template_type_arguments(type,&base,args);
    if(!count) return NULL;
    const char *package="",*owner_package=NULL; ast_node *owner=NULL,*short_owner=NULL;
    const char *short_package=NULL; bool ambiguous=false;
    for(size_t i=0;i<ctx->root->as.program.statements.len;i++) {
        ast_node *decl=ctx->root->as.program.statements.data[i];
        if(decl->kind==AST_PACKAGE_DECL) package=decl->as.package_decl.name;
        if(decl->kind!=AST_LET_STMT || !decl->native_template ||
           !decl->generic_parameters || !decl->as.let_stmt.type_name ||
           strcmp(decl->as.let_stmt.type_name,"struct")) continue;
        char qualified[1024];
        if(snprintf(qualified,sizeof(qualified),"%s%s%s",package,*package?".":"",decl->as.let_stmt.name)>=(int)sizeof(qualified)) continue;
        if(template_span_equal(base,qualified)) { owner=decl; owner_package=package; break; }
        if(template_span_equal(base,decl->as.let_stmt.name)) {
            if(short_owner) ambiguous=true;
            short_owner=decl; short_package=package;
        }
    }
    if(!owner && !ambiguous) { owner=short_owner; owner_package=short_package; }
    if(!owner || !owner->as.let_stmt.value) return NULL;
    char formals[1024];
    if(snprintf(formals,sizeof(formals),"type%s",owner->generic_parameters)>=(int)sizeof(formals) ||
       template_type_arguments(formals,&ignored,parameters)!=count) return NULL;
    ast_node *schema=owner->as.let_stmt.value; const char *annotation=NULL;
    for(size_t i=0;i<schema->as.struct_expr.field_count;i++)
        if(!strcmp(schema->as.struct_expr.field_names[i],member))
            annotation=schema->as.struct_expr.field_values.data[i]->as.string_expr.literal;
    if(!annotation) return NULL;
    char result[1024]; size_t used=0;
    for(size_t at=0;annotation[at];) {
        size_t end=at+1;
        if(isalpha((unsigned char)annotation[at]) || annotation[at]=='_')
            while(isalnum((unsigned char)annotation[end]) || annotation[end]=='_' || annotation[end]=='.') end++;
        template_type_span token={annotation+at,end-at},replacement=token;
        bool substituted=false;
        for(int a=0;a<count;a++) if(token.length==parameters[a].length && !strncmp(token.text,parameters[a].text,token.length)) {
            replacement=args[a]; substituted=true; break;
        }
        /* Resolve nominal tokens in the declaration package. Actual type
         * arguments were substituted above and keep their own identities. */
        if(!substituted && *owner_package && template_owned_nominal(ctx,owner_package,token)) {
            size_t n=strlen(owner_package);
            if(n+1>=sizeof(result)-used) return NULL;
            memcpy(result+used,owner_package,n); used+=n; result[used++]='.';
        }
        if(replacement.length>=sizeof(result)-used) return NULL;
        memcpy(result+used,replacement.text,replacement.length); used+=replacement.length; at=end;
    }
    result[used]=0;
    const char *out=dup_cstr(result);
    if(!out) error_set(ctx->err,ERR_OUT_OF_MEMORY,owner->pos.line,owner->pos.column,"symbolic field type allocation failed");
    return out;
}
#endif
