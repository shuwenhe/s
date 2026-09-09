#include "selfhost_portable.h"
static SV s_fn_main(void);
static SV s_fn_main(void){
SV v_p = s_div(s_div(s_fn_pair(s_fn_box(S_INT(1)),s_fn_box(S_INT(2))),S_C_UNSUPPORTED_64),S_C_UNSUPPORTED_73);
SV v_x = s_div(s_div(S_C_UNSUPPORTED_116,S_C_UNSUPPORTED_137),S_C_UNSUPPORTED_139);
return S_INT(0);
return S_INT(0);
}
int main(int argc,char **argv){s_init(argc,argv);SV result=s_fn_main();int status=(int)S_NUM(result);s_destroy();return status;}
