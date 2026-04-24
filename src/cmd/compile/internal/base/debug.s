package compile.internal.base

struct debug_flags {
    int align_hot
    int append
    string ast_dump
    int checkptr
    int closure
    int compress_instructions
    int escape_debug
    int gc_adjust
    int gc_start
    string gossa_hash
    int inl_funcs_with_closures
    int inl_static_init
    int loop_var
    string loop_var_hash
    int merge_locals
    int panic
    int pgo_inline
    int pgo_devirtualize
    int range_func_check
    int variable_make_threshold
    int zero_copy
    bool concurrent_ok
}

var debug = default_debug_flags()

func default_debug_flags() debug_flags {
    debug_flags {
        align_hot: 1,
        append: 0,
        ast_dump: "",
        checkptr: -1,
        closure: 0,
        compress_instructions: 1,
        escape_debug: 0,
        gc_adjust: 0,
        gc_start: 0,
        gossa_hash: "",
        inl_funcs_with_closures: 1,
        inl_static_init: 1,
        loop_var: 1,
        loop_var_hash: "",
        merge_locals: 1,
        panic: 0,
        pgo_inline: 1,
        pgo_devirtualize: 2,
        range_func_check: 1,
        variable_make_threshold: 32,
        zero_copy: 1,
        concurrent_ok: true,
    }
}

func debug_ssa(string phase, string flag, int value, string value_string) string {
    if phase == "" || flag == "" {
        return "invalid ssa debug option"
    }
    ""
}
