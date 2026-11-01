#include "selfhost_portable.h"
static SV s_fn_main(void);
static SV s_fn_main(void){
SV v_p = s_fn_Quad(S_INT(1),S_INT(2),S_INT(3),S_INT(4));
SV v_x = S_C_UNSUPPORTED_125;
return v_x;
return S_INT(0);
}
int main(int argc,char **argv){s_init(argc,argv);SV result=s_fn_main();int status=(int)S_NUM(result);s_destroy();return status;}
