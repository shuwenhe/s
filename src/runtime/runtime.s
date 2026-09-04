package src.runtime
use std.io as io
const runtime_version = "0.2.0"
extern "intrinsic" func __runtime_install_signals() ()
func runtime_init() () {
    __runtime_install_signals()
    heap_alloc_bytes = 0
    heap_live_objs   = 0
    heap_dead_objs   = 0
    heap_goal_bytes  = 4194304
    runtime_owned_object_ids = int[]()
    // S uses compiler-inserted drop by default; GC is opt-in compatibility code.
    gc_enabled = false
    gc_phase   = gc_phase_off
}

func set_max_procs(int n) int {
    old := _sched.num_p
    if n > 0 {
        _sched.num_p = n
    }
    old
}

func gc() () {
    force_gc()
}

struct mem_stats {
    int alloc
    int total_alloc
    int sys
    int num_gc
    int freed
}

func read_mem_stats() mem_stats {
    mem_stats {
        alloc:       heap_alloc_bytes, total_alloc heap_alloc_bytes + gc_total_freed, sys heap_sys_bytes, num_gc gc_run_count, freed gc_total_freed,
    }
}

func num_sroutine() int {
    len(_sched.task)
}
extern "intrinsic" func __runtime_panic(string msg) ()
extern "intrinsic" func __runtime_recover() option[string]

func panic(string msg) () {
    __runtime_panic(msg)
}

func version() string {
    runtime_version
}

func runtime_unit_name() string { "src/runtime/runtime" }

func runtime_unit_ready() int   { 1 }
