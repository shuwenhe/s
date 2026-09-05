#ifndef S_SELFHOST_PORTABLE_H
#define S_SELFHOST_PORTABLE_H
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <limits.h>
#include <sys/stat.h>
typedef uintptr_t SV;
#define S_INT(n) ((((SV)(n)) << 1) | 1)
#define S_NUM(v) (((intptr_t)(v)) >> 1)
#define S_TRUE(v) ((v) != S_INT(0))
typedef struct SString { int kind; size_t len; const char *bytes; struct SString *left,*right; } SString;
/* Compilation-session arena: explicit bulk release, no tracing or seed runtime. */
typedef struct SChunk { struct SChunk *next; size_t used,cap; max_align_t alignment; unsigned char data[]; } SChunk;
static SChunk *s_chunks;
static SV s_arguments;
static SString s_bytes[256];
static char s_byte_data[256];
static void s_panic(const char *why) { fprintf(stderr,"S bootstrap: %s\n",why); exit(70); }
static void *s_alloc(size_t n) {
    size_t a = _Alignof(max_align_t);
    if(n > SIZE_MAX-a) s_panic("allocation overflow");
    n = (n+a-1)&~(a-1);
    if(!s_chunks || n > s_chunks->cap-s_chunks->used) {
        size_t cap=n>1048576?n:1048576;
        if(cap>SIZE_MAX-sizeof(SChunk)) s_panic("allocation overflow");
        SChunk *p=malloc(sizeof(*p)+cap);
        if(!p) s_panic("out of memory");
        p->next=s_chunks; p->used=0; p->cap=cap; s_chunks=p;
    }
    void *out=s_chunks->data+s_chunks->used; s_chunks->used+=n; return out;
}
static void s_destroy(void) { while(s_chunks){SChunk *p=s_chunks; s_chunks=p->next; free(p);} }
static SString *s_str(SV v) { if(!v || (v&1)) s_panic("expected string"); return (SString*)v; }
static SV s_text(const char *p,size_t n) { SString *s=s_alloc(sizeof(*s)); *s=(SString){0,n,p,0,0};return (SV)s; }
static const char *s_flat(SString *s) {
    if(s->kind!=0 && s->kind!=1) s_panic("expected string, found array");
    if(s->bytes) return s->bytes;
    char *out=s_alloc(s->len+1);
    /* Iterative traversal avoids overflowing the C stack on long concatenations. */
    size_t cap=64,top=0,at=0;
    SString **stack=malloc(cap*sizeof(*stack));
    if(!stack) s_panic("out of memory");
    stack[top++]=s;
    while(top){
        SString *node=stack[--top];
        if(node->bytes){memcpy(out+at,node->bytes,node->len);at+=node->len;}
        else {
            if(top+2>cap){cap*=2;SString **next=realloc(stack,cap*sizeof(*stack));if(!next)s_panic("out of memory");stack=next;}
            stack[top++]=node->right;stack[top++]=node->left;
        }
    }
    free(stack);out[at]=0;s->bytes=out;return out;
}
static SV s_add(SV a,SV b){
    if((a&1)&&(b&1))return S_INT((SV)S_NUM(a)+(SV)S_NUM(b));
    SString *x=s_str(a),*y=s_str(b);
    if(x->kind==2||y->kind==2)s_panic("cannot concatenate array");
    if(!x->len)return b;if(!y->len)return a;
    if(x->len>SIZE_MAX-y->len-1)s_panic("string overflow");
    SString *s=s_alloc(sizeof(*s));*s=(SString){1,x->len+y->len,0,x,y};return (SV)s;
}
static SV s_sub(SV a,SV b){return S_INT((SV)S_NUM(a)-(SV)S_NUM(b));}
static SV s_mul(SV a,SV b){return S_INT((SV)S_NUM(a)*(SV)S_NUM(b));}
static SV s_div(SV a,SV b){intptr_t x=S_NUM(a),y=S_NUM(b);if(!y)s_panic("division by zero");return S_INT(x/y);}
static SV s_mod(SV a,SV b){intptr_t x=S_NUM(a),y=S_NUM(b);if(!y)s_panic("division by zero");return S_INT(x%y);}
static int s_cmp(SV a,SV b){
    if(a==b)return 0;
    if((a&1)&&(b&1))return (S_NUM(a)>S_NUM(b))-(S_NUM(a)<S_NUM(b));
    SString *x=s_str(a),*y=s_str(b);size_t n=x->len<y->len?x->len:y->len;
    int cmp=n?memcmp(s_flat(x),s_flat(y),n):0;
    return cmp?cmp:(x->len>y->len)-(x->len<y->len);
}
static SV s_fn_len(SV v){return S_INT(s_str(v)->len);}
static SV s_fn___host_char_at(SV v,SV index){
    SString *s=s_str(v);intptr_t i=S_NUM(index);
    if(i<0||(size_t)i>=s->len)return s_text("",0);
    return (SV)&s_bytes[(unsigned char)s_flat(s)[i]];
}
static SV s_fn___host_byte_at(SV v,SV index){
    SString *s=s_str(v);intptr_t i=S_NUM(index);
    if(i<0||(size_t)i>=s->len)return S_INT(0);
    return S_INT((unsigned char)s_flat(s)[i]);
}
static SV s_fn___host_byte_string(SV v){return (SV)&s_bytes[(unsigned char)S_NUM(v)];}
static SV s_fn___host_slice(SV v,SV begin,SV end){
    SString *s=s_str(v);intptr_t a=S_NUM(begin),b=S_NUM(end);
    if(a<0||b<a||(size_t)b>s->len)return s_text("",0);
    return s_text(s_flat(s)+a,(size_t)(b-a));
}
static SV s_index(SV v,SV index){
    SString *s=s_str(v);intptr_t i=S_NUM(index);
    if(i<0||(size_t)i>=s->len)s_panic("index out of bounds");
    if(s->kind==2)return ((const SV*)s->bytes)[i];
    return s_fn___host_char_at(v,index);
}
static char *s_cstr(SV v){SString *s=s_str(v);char *p=s_alloc(s->len+1);memcpy(p,s_flat(s),s->len);p[s->len]=0;return p;}
static SV s_fn_host_args(void){return s_arguments;}
static SV s_fn_eprintln(SV v){SString *s=s_str(v);fwrite(s_flat(s),1,s->len,stderr);fputc('\n',stderr);return S_INT(0);}
static SV s_fn___host_read_to_string(SV path){
    FILE *f=fopen(s_cstr(path),"rb");if(!f)return s_text("",0);
    if(fseek(f,0,SEEK_END)!=0){fclose(f);return s_text("",0);}long n=ftell(f);
    if(n<0||fseek(f,0,SEEK_SET)!=0){fclose(f);return s_text("",0);}
    char *p=s_alloc((size_t)n+1);size_t got=fread(p,1,(size_t)n,f);int bad=ferror(f);fclose(f);
    if(bad||got!=(size_t)n)return s_text("",0);p[got]=0;return s_text(p,got);
}
static SV s_fn___host_write_text_file(SV path,SV value){
    FILE *f=fopen(s_cstr(path),"wb");if(!f)return S_INT(1);SString *s=s_str(value);
    size_t got=fwrite(s_flat(s),1,s->len,f);int rc=fclose(f);return S_INT(rc||got!=s->len);
}
static SV s_fn___host_make_executable(SV path){return S_INT(chmod(s_cstr(path),0755)!=0);}
static void s_init(int argc,char **argv){
    for(int i=0;i<256;i++){s_byte_data[i]=(char)i;s_bytes[i]=(SString){0,1,&s_byte_data[i],0,0};}
    SV *items=s_alloc((size_t)argc*sizeof(*items));
    for(int i=0;i<argc;i++)items[i]=s_text(argv[i],strlen(argv[i]));
    SString *a=s_alloc(sizeof(*a));*a=(SString){2,(size_t)argc,(const char*)items,0,0};s_arguments=(SV)a;
}
#endif
