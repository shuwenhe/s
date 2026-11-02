/* Native single-threaded runtime collector.
 * Non-moving conservative mark/sweep, power-of-two objects in mmap slabs.
 * No libc, C seed, subprocesses, threads or compiler delegation.
 */
typedef unsigned long U;
typedef unsigned char B;
#define CLASSES 59
#define MAX_SLABS 8192
#define PERIOD (32UL << 20)
struct slab { U base, bytes, shift, count; B *state; U state_bytes; };
static struct slab slabs[MAX_SLABS];
static U slab_count, free_head[CLASSES], allocated_since_gc, period = PERIOD;
static U *queue, queue_count, queue_capacity;
U s_native_gc_stack_top;
extern U s_native_gc_roots_begin, s_native_gc_roots_end;

static long syscall6(long n, long a, long b, long c, long d, long e, long f) {
    register long r10 __asm__("r10") = d;
    register long r8 __asm__("r8") = e;
    register long r9 __asm__("r9") = f;
    long result;
    __asm__ volatile("syscall" : "=a"(result) : "a"(n), "D"(a), "S"(b), "d"(c), "r"(r10), "r"(r8), "r"(r9) : "rcx", "r11", "memory");
    return result;
}
static void die(void) {
    syscall6(60,126,0,0,0,0,0);
    __builtin_unreachable();
}
static U map(U bytes) {
    U p = syscall6(9,0,bytes,3,34,-1,0);
    return p >= (U)-4095 ? 0 : p;
}
static void unmap(U base, U bytes) { syscall6(11,base,bytes,0,0,0,0); }
static void mark(U candidate) {
    if(!slab_count || candidate < slabs[0].base || candidate >= slabs[slab_count-1].base + slabs[slab_count-1].bytes)return;
    U lo=0, hi=slab_count;
    while (lo < hi) {
        U mid=lo+(hi-lo)/2;
        if (slabs[mid].base <= candidate) lo=mid+1; else hi=mid;
    }
    if (!lo) return;
    struct slab *s=&slabs[lo-1];
    if (candidate-s->base >= s->bytes) return;
    U index=(candidate-s->base)>>s->shift;
    if (s->state[index] != 1) return;
    s->state[index]=2;
    if (queue_count == queue_capacity) {
        U capacity=queue_capacity ? queue_capacity*2 : 4096;
        if(capacity < queue_capacity || capacity > (~0UL)/8)die();
        U *grown=(U*)map(capacity*8);
        if(!grown)die();
        for(U q=0;q<queue_count;++q)grown[q]=queue[q];
        if(queue)unmap((U)queue,queue_capacity*8);
        queue=grown;queue_capacity=capacity;
    }
    queue[queue_count++]=s->base+(index<<s->shift);
}
static void scan(U begin, U end) {
    for (U p=begin; p<end; p+=8) mark(*(U*)p);
}
static void collect(U root_stack) {
    /* Object/library entries have no standalone stack boundary, and values may
     * escape to C. Preserve their original process-lifetime allocation policy;
     * only the standalone _start opts into tracing collection. */
    if(!s_native_gc_stack_top) {
        allocated_since_gc=0;period=~0UL;return;
    }
    queue_count=0;
    scan(root_stack,s_native_gc_stack_top);
    scan((U)&s_native_gc_roots_begin,(U)&s_native_gc_roots_end);
    for (U q=0; q<queue_count; ++q) {
        U p=queue[q], lo=0, hi=slab_count;
        while (lo<hi) { U m=lo+(hi-lo)/2; if(slabs[m].base<=p)lo=m+1;else hi=m; }
        struct slab *s=&slabs[lo-1];
        scan(p,p+(1UL<<s->shift));
    }
    for(U c=0;c<CLASSES;++c)free_head[c]=0;
    U retained=0, live_bytes=0;
    for(U i=0;i<slab_count;++i) {
        struct slab s=slabs[i];
        U live=0;
        for(U j=0;j<s.count;++j)if(s.state[j]==2)++live;
        if(!live) { unmap(s.base,s.bytes);unmap((U)s.state,s.state_bytes);continue; }
        for(U j=0;j<s.count;++j) {
            if(s.state[j]==2) {s.state[j]=1;live_bytes+=1UL<<s.shift;continue;}
            s.state[j]=0;
            U p=s.base+(j<<s.shift);
            *(U*)p=free_head[s.shift];free_head[s.shift]=p;
        }
        slabs[retained++]=s;
    }
    slab_count=retained;
    allocated_since_gc=0;
    period=live_bytes>PERIOD ? live_bytes : PERIOD;
}
static int add_slab(U shift) {
    if(slab_count==MAX_SLABS)return 0;
    U bytes=1UL<<shift;
    if(bytes<(1UL<<20))bytes=1UL<<20;
    U base=map(bytes);
    if(!base)return 0;
    U count=bytes>>shift, state_bytes=(count+4095)&~4095UL;
    B *state=(B*)map(state_bytes);
    if(!state){unmap(base,bytes);return 0;}
    U index=slab_count;
    while(index && slabs[index-1].base>base){slabs[index]=slabs[index-1];--index;}
    slabs[index]=(struct slab){base,bytes,shift,count,state,state_bytes};
    ++slab_count;
    for(U j=0;j<count;++j){U p=base+(j<<shift);*(U*)p=free_head[shift];free_head[shift]=p;}
    return 1;
}
/* root_stack points above this C frame, at the assembly wrapper's register dump. */
U s_native_gc_alloc(U size,U root_stack) {
    U shift=4;
    while((1UL<<shift)<size){if(++shift==CLASSES)die();}
    if(allocated_since_gc>=period)collect(root_stack);
    if(!free_head[shift] && !add_slab(shift)) {
        collect(root_stack);
        if(!free_head[shift] && !add_slab(shift))die();
    }
    U p=free_head[shift];free_head[shift]=*(U*)p;
    U lo=0,hi=slab_count;
    while(lo<hi){U m=lo+(hi-lo)/2;if(slabs[m].base<=p)lo=m+1;else hi=m;}
    struct slab *s=&slabs[lo-1];s->state[(p-s->base)>>shift]=1;
    U bytes=1UL<<shift;
    for(U i=0;i<bytes;i+=8)*(U*)(p+i)=0;
    allocated_since_gc+=bytes;
    return p;
}
