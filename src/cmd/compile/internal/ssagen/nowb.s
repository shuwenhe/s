package compile.internal.ssagen

func is_nowritebarrier_fn(string fn_name) bool {
    if fn_name == "runtime.gcMark" {
        return true
    }
    if fn_name == "runtime.gcBgMarkWorker" {
        return true
    }
    if fn_name == "runtime.wbBufFlush" {
        return true
    }
    false
}

func should_emit_writebarrier(string fn_name, bool has_heap_ptr_store, bool global_store) bool {
    if !has_heap_ptr_store {
        return false
    }
    if is_nowritebarrier_fn(fn_name) {
        return false
    }
    if global_store {
        return true
    }
    true
}
