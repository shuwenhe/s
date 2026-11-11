#define _POSIX_C_SOURCE 200809L
/* Canonical S raw ABI -> system OpenSSL. No database client dependency.
 * S owns the TCP fd; this bridge owns only SSL/SSL_CTX. Single-threaded sessions.
 * Every operation is bounded by an overall monotonic deadline. */
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef long I;
typedef struct {I length;unsigned char bytes[];} S;
struct session {SSL_CTX *ctx;SSL *ssl;I generation;int fd;};
static struct session sessions[64];
static I now_ns(void){struct timespec t;if(clock_gettime(CLOCK_MONOTONIC,&t))return -errno;return (I)t.tv_sec*1000000000+t.tv_nsec;}
static I deadline_for(I timeout){if(timeout < -1||timeout>INT_MAX)return -EINVAL;if(timeout==-1)return 0;I now=now_ns();return now<0?now:now+timeout*1000000;}
static I wait_ssl(int fd,int events,I deadline,I nonblocking){
    for(;;){
        I remaining=-1;
        if(deadline){I now=now_ns();if(now<0)return now;I left=deadline-now;remaining=left>0?(left+999999)/1000000:0;}
        struct pollfd p={fd,(short)events,0};int status=poll(&p,1,(int)remaining);
        if(status<0&&errno==EINTR)continue;
        if(status<0)return -errno;
        if(!status)return nonblocking?-EAGAIN:-ETIMEDOUT;
        if(p.revents&POLLNVAL)return -EBADF;
        return 0;
    }
}
static char *copy_string(S*s){
    if(!s||s->length<0||s->length>4096||memchr(s->bytes,0,(size_t)s->length))return NULL;
    char *p=malloc((size_t)s->length+1);if(!p)return NULL;
    memcpy(p,s->bytes,(size_t)s->length);p[s->length]=0;return p;
}
struct pipe_guard {sigset_t previous;int pending;};
static int guard_begin(struct pipe_guard*g){
    sigset_t blocked,pending;sigemptyset(&blocked);sigaddset(&blocked,SIGPIPE);
    if(sigprocmask(SIG_BLOCK,&blocked,&g->previous))return -errno;
    if(sigpending(&pending)){int error=errno;sigprocmask(SIG_SETMASK,&g->previous,NULL);return -error;}
    g->pending=sigismember(&pending,SIGPIPE);return 0;
}
static void guard_end(struct pipe_guard*g){
    int saved=errno;sigset_t pending,one;struct timespec zero={0,0};
    if(!g->pending&&!sigpending(&pending)&&sigismember(&pending,SIGPIPE)){
        sigemptyset(&one);sigaddset(&one,SIGPIPE);
        while(sigtimedwait(&one,NULL,&zero)<0&&errno==EINTR){}
    }
    sigprocmask(SIG_SETMASK,&g->previous,NULL);errno=saved;
}
static struct session *lookup(I handle){
    I index=(handle&127)-1,generation=handle>>7;
    if(handle<=0||index<0||index>=64||!sessions[index].ssl||sessions[index].generation!=generation)return NULL;
    return &sessions[index];
}
static I ssl_problem(SSL*ssl,int result,int fd,I deadline,I nonblocking){
    int error=SSL_get_error(ssl,result);
    if(error==SSL_ERROR_WANT_READ)return wait_ssl(fd,POLLIN,deadline,nonblocking);
    if(error==SSL_ERROR_WANT_WRITE)return wait_ssl(fd,POLLOUT,deadline,nonblocking);
    if(error==SSL_ERROR_SYSCALL&&errno==EINTR)return 0;
    if(SSL_get_verify_result(ssl)!=X509_V_OK)return -EACCES;
    return -EPROTO;
}
I s_tls_connect(I fd,S*hostname,S*ca_path,I timeout){
    if(fd<0||fd>INT_MAX||!hostname||!hostname->length)return -EINVAL;
    I deadline=deadline_for(timeout);if(deadline<0)return deadline;
    int flags=fcntl((int)fd,F_GETFL);if(flags<0)return -errno;
    if(!(flags&O_NONBLOCK))return -EINVAL;
    char *host=copy_string(hostname),*ca=copy_string(ca_path);
    if(!host||!ca){free(host);free(ca);return -EINVAL;}
    SSL_CTX *ctx=SSL_CTX_new(TLS_client_method());SSL *ssl=NULL;I status=-EACCES;
    if(!ctx)goto fail;
    if(!SSL_CTX_set_min_proto_version(ctx,TLS1_2_VERSION))goto fail;
    SSL_CTX_set_verify(ctx,SSL_VERIFY_PEER,NULL);
    if(*ca){if(!SSL_CTX_load_verify_locations(ctx,ca,NULL))goto fail;}
    else if(!SSL_CTX_set_default_verify_paths(ctx))goto fail;
    ssl=SSL_new(ctx);if(!ssl)goto fail;
    if(!SSL_set1_host(ssl,host)||!SSL_set_tlsext_host_name(ssl,host)||!SSL_set_fd(ssl,(int)fd))goto fail;
    SSL_set_mode(ssl,SSL_MODE_ENABLE_PARTIAL_WRITE|SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER);
    struct pipe_guard guard;status=guard_begin(&guard);if(status<0)goto fail;
    for(;;){
        ERR_clear_error();errno=0;int result=SSL_connect(ssl);
        if(result==1){status=SSL_get_verify_result(ssl)==X509_V_OK?0:-EACCES;break;}
        status=ssl_problem(ssl,result,(int)fd,deadline,timeout==0);if(status<0)break;
    }
    guard_end(&guard);
    if(status<0)goto fail;
    for(I i=0;i<64;i++)if(!sessions[i].ssl&&sessions[i].generation<(LONG_MAX>>7)){
        sessions[i].generation++;sessions[i].ctx=ctx;sessions[i].ssl=ssl;sessions[i].fd=(int)fd;
        free(host);free(ca);return (sessions[i].generation<<7)|(i+1);
    }
    status=-EMFILE;
fail:
    SSL_free(ssl);SSL_CTX_free(ctx);free(host);free(ca);return status;
}
I s_tls_send(I handle,S*data,I offset,I timeout){
    struct session*s=lookup(handle);if(!s)return -EBADF;
    if(!data||data->length<0||offset<0||offset>data->length)return -EINVAL;
    I deadline=deadline_for(timeout);if(deadline<0)return deadline;
    size_t count=(size_t)(data->length-offset);if(count>65536)count=65536;
    if(!count)return 0;
    struct pipe_guard guard;I status=guard_begin(&guard);if(status<0)return status;
    for(;;){
        size_t written=0;ERR_clear_error();errno=0;
        int result=SSL_write_ex(s->ssl,data->bytes+offset,count,&written);
        if(result==1){status=(I)written;break;}
        status=ssl_problem(s->ssl,result,s->fd,deadline,timeout==0);if(status<0)break;
    }
    guard_end(&guard);return status;
}
I s_tls_receive(I handle,I*buffer,I timeout){
    struct session*s=lookup(handle);if(!s)return -EBADF;
    if(!buffer||buffer[0]<1||buffer[0]>65536)return -EINVAL;
    I deadline=deadline_for(timeout);if(deadline<0)return deadline;
    unsigned char bytes[65536];I status;
    struct pipe_guard guard;status=guard_begin(&guard);if(status<0)return status;
    for(;;){
        size_t received=0;ERR_clear_error();errno=0;
        int result=SSL_read_ex(s->ssl,bytes,(size_t)buffer[0],&received);
        if(result==1){for(size_t i=0;i<received;i++)buffer[i+1]=bytes[i];status=(I)received;break;}
        int error=SSL_get_error(s->ssl,result);
        if(error==SSL_ERROR_ZERO_RETURN){status=0;break;}
        status=ssl_problem(s->ssl,result,s->fd,deadline,timeout==0);if(status<0)break;
    }
    guard_end(&guard);
    OPENSSL_cleanse(bytes,sizeof(bytes));return status;
}
I s_tls_close(I handle){
    struct session*s=lookup(handle);if(!s)return -EBADF;
    SSL *ssl=s->ssl;SSL_CTX *ctx=s->ctx;s->ssl=NULL;s->ctx=NULL;s->fd=-1;
    struct pipe_guard guard;int guarded=guard_begin(&guard);
    /* Best-effort close_notify on a nonblocking borrowed fd. Never wait forever. */
    if(!guarded){ERR_clear_error();SSL_shutdown(ssl);guard_end(&guard);}
    SSL_free(ssl);SSL_CTX_free(ctx);return guarded;
}
