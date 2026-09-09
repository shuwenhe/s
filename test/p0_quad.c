#include "compiler_runtime.h"
typedef struct S_Quad {
    int64_t a;
    int64_t b;
    int64_t c;
    int64_t d;
} S_Quad;
static void compiler_drop_user_Quad(S_Quad *value);
static inline __attribute__((unused)) S_Quad *compiler_make_Quad(int64_t p0, int64_t p1, int64_t p2, int64_t p3) {
    S_Quad *value = (S_Quad *)malloc(sizeof(*value));
    if (!value) compiler_trap("allocation failed");
    value->a = p0;
    value->b = p1;
    value->c = p2;
    value->d = p3;
#ifdef S_COMPILER_CHECK_ALLOCATIONS
    ++compiler_objects;
#endif
    return value;
}
static inline __attribute__((unused)) void compiler_drop_fields_Quad(S_Quad *value) {
}
static inline __attribute__((unused)) void compiler_drop_owned_Quad(S_Quad **owner) {
    if (*owner) { compiler_drop_user_Quad(*owner); compiler_drop_fields_Quad(*owner); free(*owner); *owner = NULL;
#ifdef S_COMPILER_CHECK_ALLOCATIONS
    --compiler_objects;
#endif
    }
}
static inline __attribute__((unused)) S_Quad *compiler_move_Quad(S_Quad **source) {
    S_Quad *value = *source;
    *source = NULL;
    return value;
}
static void compiler_drop_user_Quad(S_Quad *value) { (void)value; }
int main(void)
{
{
S_Quad *s_v0 = compiler_make_Quad(INT64_C(1),INT64_C(2),INT64_C(3),INT64_C(4));
(void)s_v0;
int64_t s_v1 = s_v0->c;
(void)s_v1;
{ int64_t compiler_result = s_v1;
compiler_drop_owned_Quad(&s_v0);
return compiler_finish(compiler_result); }
}
return compiler_finish(0);
}
