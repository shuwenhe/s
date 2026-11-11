/* Linux getrandom only. No time, seed, deterministic PRNG or fallback entropy. */
#ifdef S_TCP_SEED
#define CRYPTO_RANDOM_NAME s_crypto_seed_random
#else
#define CRYPTO_RANDOM_NAME s_crypto_random
#endif
T *CRYPTO_RANDOM_NAME(T count_value){
    T count=tcp_in(count_value),status=0,used=0;
    unsigned char bytes[65536];
    if(count<0||count>65536)status=-22;
    else while(used<count){
        T result=tcp_sys(318,(T)(bytes+used),count-used,0,0,0,0);
        if(result==-4)continue;
        if(result<0){status=result;break;}
        if(!result){status=-5;break;}
        used+=result;
    }
    T *output=tcp_array(status<0?1:count+1);
    if(!output)return 0;
    tcp_set(output,0,status);
    if(!status)for(T i=0;i<count;i++)tcp_set(output,i+1,bytes[i]);
    /* Best effort volatile clearing of the temporary entropy buffer. */
    volatile unsigned char *clear=bytes;
    for(T i=0;i<used;i++)clear[i]=0;
    return output;
}
