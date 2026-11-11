/* Freestanding Linux x86-64 runtime. Regenerate S assembly with extensions_generate.py. */
typedef long I;
#define MAX_I 0x7fffffffffffffffL
#define MAX_ARRAY_LENGTH ((MAX_I - 8) / 8)
typedef struct { I n; unsigned char p[]; } S;
extern void *alloc(I) __asm__(".Ls_native_alloc");
extern char *toc(S*) __asm__(".Ls_native_to_c");
extern S *readfile(S*) __asm__(".Ls_native_read_file");
extern I run(I*) __asm__(".Ls_native_run_argv");
extern char **envp __asm__(".Ls_native_envp");
static I sys(I n,I a,I b,I c,I d){register I r10 __asm__("r10")=d;register I r8 __asm__("r8")=0;register I r9 __asm__("r9")=0;I r;__asm__ volatile("syscall":"=a"(r):"a"(n),"D"(a),"S"(b),"d"(c),"r"(r10),"r"(r8),"r"(r9):"rcx","r11","memory");return r;}
static void copy(unsigned char*d,unsigned char*s,I n){for(I i=0;i<n;i++)d[i]=s[i];}
I s_ext_socket(I a,I b,I c){return sys(41,a,b,c,0);}
I s_ext_close(I fd){return sys(3,fd,0,0,0);}
I s_ext_write(I fd,S*s){if(!s||s->n<0)return -22;I r;do {r=sys(44,fd,(I)s->p,s->n,16384);}while(r==-4);if(r==-88){do{r=sys(1,fd,(I)s->p,s->n,0);}while(r==-4);}return r;}
S*s_ext_read(I fd,I count){if(count<0||count>0x7fffffff)return 0;S*s=alloc(count+8);if(!s)return 0;I r;do{r=sys(0,fd,(I)s->p,count,0);}while(r==-4);if(r<0)return 0;s->n=r;return s;}
I s_ext_connect(I fd,S*ip,I port,I family){unsigned char a[16]={0};if(family!=2||!ip||port<0||port>65535)return -22;a[0]=2;a[2]=port>>8;a[3]=port;I at=0;for(I part=0;part<4;part++){I v=0,n=0;while(at<ip->n&&ip->p[at]>='0'&&ip->p[at]<='9'){v=v*10+ip->p[at++]-'0';if(v>255)return -22;n++;}if(!n)return -22;a[4+part]=v;if(part<3){if(at>=ip->n||ip->p[at++]!='.')return -22;}}if(at!=ip->n)return -22;return sys(42,fd,(I)a,16,0);}
I s_ext_exists(S*p){char*c=toc(p);return c&&sys(21,(I)c,0,0,0)==0;}
I s_ext_env_exists(S*k){if(!k||!envp)return 0;for(I j=0;envp[j];j++){I i=0;while(i<k->n&&envp[j][i]&&envp[j][i]==k->p[i])i++;if(i==k->n&&envp[j][i]=='=')return 1;}return 0;}
I*s_ext_read_range(S*p,I start,I count){if(start<0||count<0||count>MAX_ARRAY_LENGTH)return 0;char*c=toc(p);if(!c)return 0;I fd=sys(257,-100,(I)c,0,0);if(fd<0)return 0;if(sys(8,fd,start,0,0)<0){s_ext_close(fd);return 0;}I*a=alloc((count+1)*8);if(!a){s_ext_close(fd);return 0;}I used=0;unsigned char buf[4096];while(used<count){I n=count-used;if(n>4096)n=4096;I r=sys(0,fd,(I)buf,n,0);if(r==-4)continue;if(r<0){s_ext_close(fd);return 0;}if(!r)break;for(I i=0;i<r;i++)a[++used]=buf[i];}a[0]=used;s_ext_close(fd);return a;}
I*s_ext_read_binary(S*p){S*s=readfile(p);if(!s)return 0;if(s->n<0||s->n>MAX_ARRAY_LENGTH)return 0;I*a=alloc((s->n+1)*8);if(!a)return 0;a[0]=s->n;for(I i=0;i<s->n;i++)a[i+1]=s->p[i];return a;}
I s_ext_write_binary(S*p,I*a){char*c=toc(p);if(!c||!a||a[0]<0)return -1;I fd=sys(257,-100,(I)c,577,438);if(fd<0)return -1;unsigned char buf[4096];I at=0;while(at<a[0]){I n=a[0]-at;if(n>4096)n=4096;for(I i=0;i<n;i++)buf[i]=a[at+i+1];I off=0;while(off<n){I r=sys(1,fd,(I)(buf+off),n-off,0);if(r==-4)continue;if(r<=0){s_ext_close(fd);return -1;}off+=r;}at+=n;}return s_ext_close(fd)<0?-1:0;}
/* The native allocator wrapper saves every GP register before tracing the stack.
 * Thus out/next and input pointers held in C registers remain collector roots. */
S *s_ext_capture(I *args) {
    int fds[2];
    if(sys(22,(I)fds,0,0,0)<0) return 0;
    I pid=sys(57,0,0,0,0);
    if(pid<0) {
        s_ext_close(fds[0]);
        s_ext_close(fds[1]);
        return 0;
    }
    if(!pid) {
        s_ext_close(fds[0]);
        if(sys(33,fds[1],1,0,0)<0) sys(60,127,0,0,0);
        /* A caller may have closed stdout before invoking capture. */
        if(fds[1]!=1) s_ext_close(fds[1]);
        I status=run(args);
        sys(60,status<0?127:status,0,0,0);
        __builtin_unreachable();
    }
    s_ext_close(fds[1]);
    I cap=4096,n=0;
    S *out=alloc(cap+8);
    I failed=!out;
    unsigned char buf[4096];
    for(;;) {
        I r=sys(0,fds[0],(I)buf,4096,0);
        if(r==-4) continue;
        if(r<0) { failed=1; break; }
        if(!r) break;
        /* Keep draining after allocation failure so the child cannot block
         * on a full pipe while the parent waits for it. */
        if(failed) continue;
        if(r>MAX_I-8-n) { failed=1; continue; }
        I required=n+r;
        if(required>cap) {
            cap=required>(MAX_I-8)/2 ? required : required*2;
            S *next=alloc(cap+8);
            if(!next) { failed=1; continue; }
            copy(next->p,out->p,n);
            out=next;
        }
        copy(out->p+n,buf,r);
        n=required;
    }
    s_ext_close(fds[0]);
    int status=0;
    I waited;
    do { waited=sys(61,pid,(I)&status,0,0); } while(waited==-4);
    if(failed||waited<0||status) return 0;
    out->n=n;
    return out;
}

/* Shared TCP operations use an explicitly selected value ABI. */
#include "../../../../runtime/native_tcp.h"
#include "../../../../runtime/native_crypto_random.h"
