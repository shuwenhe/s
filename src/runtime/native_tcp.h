/* Linux/amd64 TCP OS boundary. No database protocol, libc or client library.
 * Compile for the canonical raw ABI or the Seed tagged ABI explicitly. */
typedef long T;
#ifdef S_TCP_SEED
extern void *s_alloc(T);
extern T s_integer_pack(T);
extern T s_string_byte_raw(T,T);
#define TCP_FN(name) s_tcp_seed_##name
static T tcp_in(T v){return v&1?v>>1:((T*)v)[1];}
static T tcp_out(T v){return s_integer_pack(v);}
static void *tcp_alloc(T n){return s_alloc(n);}
static T tcp_strlen(T s){return s?((T*)s)[1]:0;}
static T tcp_byte(T s,T i){return s_string_byte_raw(s,i);}
static T *tcp_array(T n){T*a=tcp_alloc(16+8*n);if(a){a[0]=4;a[1]=n;}return a;}
static void tcp_set(T*a,T i,T v){a[i+2]=tcp_out(v);}
#else
extern void *alloc(T) __asm__(".Ls_native_alloc");
#define TCP_FN(name) s_tcp_##name
static T tcp_in(T v){return v;}
static T tcp_out(T v){return v;}
static void *tcp_alloc(T n){return alloc(n);}
static T tcp_strlen(T s){return s?((T*)s)[0]:0;}
static T tcp_byte(T s,T i){return ((unsigned char*)s)[8+i];}
static T *tcp_array(T n){T*a=tcp_alloc(8+8*n);if(a)a[0]=n;return a;}
static void tcp_set(T*a,T i,T v){a[i+1]=v;}
#endif
static T tcp_sys(T n,T a,T b,T c,T d,T e,T f){
    register T r10 __asm__("r10")=d;
    register T r8 __asm__("r8")=e;
    register T r9 __asm__("r9")=f;
    T r;
    __asm__ volatile("syscall":"=a"(r):"a"(n),"D"(a),"S"(b),"d"(c),"r"(r10),"r"(r8),"r"(r9):"rcx","r11","memory");
    return r;
}
static T tcp_now(void){T ts[2];T r=tcp_sys(228,1,(T)ts,0,0,0,0);return r<0?r:ts[0]*1000000000+ts[1];}
static T tcp_deadline(T timeout){
    if(timeout < -1 || timeout>2147483647)return -22;
    if(timeout==-1)return 0;
    T now=tcp_now();if(now<0)return now;
    return now+timeout*1000000;
}
static T tcp_wait(T fd,T events,T deadline,T nonblocking){
    if(fd<0||fd>2147483647)return -9;
    struct {int fd;short events,revents;} p={(int)fd,(short)events,0};
    for(;;){
        T timeout=-1;
        if(deadline){T now=tcp_now();if(now<0)return now;T left=deadline-now;timeout=left>0?(left+999999)/1000000:0;}
        T r=tcp_sys(7,(T)&p,1,timeout,0,0,0);
        if(r==-4)continue;
        if(r<0)return r;
        if(!r)return nonblocking?-11:-110;
        if(p.revents&32)return -9;
        return 0; /* ERR/HUP proceed to the operation for exact errno/EOF. */
    }
}
static void tcp_address(unsigned char*a,T ip,T port){
    for(T i=0;i<16;i++)a[i]=0;
    a[0]=2;a[2]=port>>8;a[3]=port;
    for(T i=0;i<4;i++)a[4+i]=(unsigned long)ip>>(i*8);
}
T TCP_FN(socket)(T family,T kind,T protocol){return tcp_out(tcp_sys(41,tcp_in(family),tcp_in(kind),tcp_in(protocol),0,0,0));}
T TCP_FN(close)(T fd){return tcp_out(tcp_sys(3,tcp_in(fd),0,0,0,0,0));}
T TCP_FN(dial)(T ip_value,T port_value,T timeout_value){
    T ip=tcp_in(ip_value),port=tcp_in(port_value),timeout=tcp_in(timeout_value);
    if(ip<0||ip>4294967295L||port<1||port>65535)return tcp_out(-22);
    T deadline=tcp_deadline(timeout);if(deadline<0)return tcp_out(deadline);
    T fd=tcp_sys(41,2,1|2048|524288,0,0,0,0);if(fd<0)return tcp_out(fd);
    unsigned char a[16];tcp_address(a,ip,port);
    T r=tcp_sys(42,fd,(T)a,16,0,0,0);
    if(r==-115){
        r=tcp_wait(fd,4,deadline,timeout==0);
        if(!r){int error=0;unsigned int n=4;r=tcp_sys(55,fd,1,4,(T)&error,(T)&n,0);if(!r)r=-error;}
    }
    if(r<0){tcp_sys(3,fd,0,0,0,0,0);return tcp_out(r);}
    return tcp_out(fd);
}
T TCP_FN(listen)(T ip_value,T port_value,T backlog_value){
    T ip=tcp_in(ip_value),port=tcp_in(port_value),backlog=tcp_in(backlog_value);
    if(ip<0||ip>4294967295L||port<0||port>65535||backlog<1||backlog>65535)return tcp_out(-22);
    T fd=tcp_sys(41,2,1|2048|524288,0,0,0,0);if(fd<0)return tcp_out(fd);
    int yes=1;T r=tcp_sys(54,fd,1,2,(T)&yes,4,0);
    unsigned char a[16];tcp_address(a,ip,port);
    if(!r)r=tcp_sys(49,fd,(T)a,16,0,0,0);
    if(!r)r=tcp_sys(50,fd,backlog,0,0,0,0);
    if(r<0){tcp_sys(3,fd,0,0,0,0,0);return tcp_out(r);}
    return tcp_out(fd);
}
T TCP_FN(port)(T fd_value){
    T fd=tcp_in(fd_value);unsigned char a[16];unsigned int n=16;
    T r=tcp_sys(51,fd,(T)a,(T)&n,0,0,0);
    if(r<0)return tcp_out(r);
    if(n!=16||a[0]!=2)return tcp_out(-97);
    return tcp_out((T)a[2]*256+a[3]);
}
T TCP_FN(accept)(T fd_value,T timeout_value){
    T fd=tcp_in(fd_value),timeout=tcp_in(timeout_value);
    T deadline=tcp_deadline(timeout);if(deadline<0)return tcp_out(deadline);
    for(;;){
        T r=tcp_wait(fd,1,deadline,timeout==0);if(r<0)return tcp_out(r);
        r=tcp_sys(288,fd,0,0,2048|524288,0,0);
        if(r==-4||r==-11)continue;
        return tcp_out(r);
    }
}
T TCP_FN(send)(T fd_value,T text,T offset_value,T timeout_value){
    T fd=tcp_in(fd_value),offset=tcp_in(offset_value),timeout=tcp_in(timeout_value),length=tcp_strlen(text);
    if(!text||offset<0||offset>length)return tcp_out(-22);
    T deadline=tcp_deadline(timeout);if(deadline<0)return tcp_out(deadline);
    T count=length-offset;if(count>65536)count=65536;
    if(!count)return tcp_out(0);
    unsigned char bytes[65536];for(T i=0;i<count;i++)bytes[i]=tcp_byte(text,offset+i);
    for(;;){
        T r=tcp_wait(fd,4,deadline,timeout==0);if(r<0)return tcp_out(r);
        r=tcp_sys(44,fd,(T)bytes,count,16384|64,0,0); /* NOSIGNAL | DONTWAIT */
        if(r==-4||r==-11)continue;
        return tcp_out(r);
    }
}
T *TCP_FN(receive)(T fd_value,T max_value,T timeout_value){
    T fd=tcp_in(fd_value),maximum=tcp_in(max_value),timeout=tcp_in(timeout_value);
    T result=0,deadline=tcp_deadline(timeout);
    unsigned char bytes[65536];
    if(maximum<1||maximum>65536)result=-22;
    else if(deadline<0)result=deadline;
    else for(;;){
        result=tcp_wait(fd,1,deadline,timeout==0);if(result<0)break;
        result=tcp_sys(45,fd,(T)bytes,maximum,64,0,0);
        if(result!=-4&&result!=-11)break;
    }
    T *array=tcp_array(result<0?1:result+1);if(!array)return 0;
    tcp_set(array,0,result<0?result:0);
    if(result>0)for(T i=0;i<result;i++)tcp_set(array,i+1,bytes[i]);
    return array;
}
/* Legacy __sys_connect adapter: preserve its existing raw IPv4/errno contract. */
T TCP_FN(connect)(T fd_value,T host,T port_value,T family_value){
    T fd=tcp_in(fd_value),port=tcp_in(port_value),family=tcp_in(family_value),ip=0,index=0;
    if(!host||port<0||port>65535||family!=2)return tcp_out(-22);
    for(T part=0;part<4;part++){
        T value=0,digits=0;
        while(index<tcp_strlen(host)){
            T byte=tcp_byte(host,index);if(byte<48||byte>57)break;
            value=value*10+byte-48;if(value>255)return tcp_out(-22);index++;digits++;
        }
        if(!digits)return tcp_out(-22);
        ip|=value<<(part*8);
        if(part<3){if(index>=tcp_strlen(host)||tcp_byte(host,index++)!=46)return tcp_out(-22);}
    }
    if(index!=tcp_strlen(host))return tcp_out(-22);
    unsigned char a[16];tcp_address(a,ip,port);
    return tcp_out(tcp_sys(42,fd,(T)a,16,0,0,0));
}
