#include "selfhost_portable.h"
static SV s_fn_main(void);
static SV s_fn_main(void){
SV v_x = S_INT(42);
return v_x;
return S_INT(0);
}
int main(int argc,char **argv){s_init(argc,argv);SV result=s_fn_main();int status=(int)S_NUM(result);s_destroy();return status;}
