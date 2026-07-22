package src.runtime

use std.vec.vec

const GC_PHASE_OFF   = 0
const GC_PHASE_MARK  = 1
const GC_PHASE_SWEEP = 2

var gc_phase        = GC_PHASE_OFF
var gc_run_count    = 0
var gc_total_freed  = 0
var gc_enabled      = true

extern "intrinsic" func __gc_stw_start() ()
extern "intrinsic" func __gc_stw_stop() ()

extern "intrinsic" func __runtime_nanotime() int

func gc_trigger() () {
    if !gc_enabled {
        return
    }
    if heap_alloc_bytes < heap_goal_bytes {
        return
    }
    run_gc()
}

func run_gc() () {
    if gc_phase != GC_PHASE_OFF {
        return
    }

    let t0 = __runtime_nanotime()

    __gc_stw_start()

    gc_phase = GC_PHASE_MARK
    mark_init()
    mark_roots()
    drain_mark_queue()

    gc_phase = GC_PHASE_SWEEP
    let freed = sweep_pass()
    gc_total_freed = gc_total_freed + freed

    gc_run_count = gc_run_count + 1
    gc_phase     = GC_PHASE_OFF

    heap_goal_bytes = heap_alloc_bytes * 2
    if heap_goal_bytes < 4194304 {
        heap_goal_bytes = 4194304
    }

    __gc_stw_stop()
}

func force_gc() () {
    run_gc()
}

struct GcStats {
    int phase
    int heap_alloc
    int heap_goal
    int num_gc
    int total_freed
    int live_objects
}

func gc_stats() GcStats {
    GcStats {
        phase:        gc_phase,
        heap_alloc:   heap_alloc_bytes,
        heap_goal:    heap_goal_bytes,
        num_gc:       gc_run_count,
        total_freed:  gc_total_freed,
        live_objects: heap_live_objs,
    }
}

func gc_disable() () { gc_enabled = false }
func gc_enable()  () { gc_enabled = true  }

func mgc_unit_name() string { "src/runtime/mgc" }
func mgc_unit_ready() int   { 1 }
