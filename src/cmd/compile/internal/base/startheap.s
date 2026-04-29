package compile.internal.base

struct start_heap_state {
    int requested_heap_goal
    int derate_break
    int derate_lo_pct
    int derate_hi_pct
    bool log_heap_tweaks
    int current_gogc
    int original_gogc
    bool active
}

let start_heap = start_heap_state {
    requested_heap_goal: 0,
    derate_break: 600,
    derate_lo_pct: 70,
    derate_hi_pct: 55,
    log_heap_tweaks: false,
    current_gogc: 100,
    original_gogc: 100,
    active: false,
}

func gogc_derate(int gogc) int {
    if gogc < start_heap.derate_break {
        return (gogc * start_heap.derate_lo_pct) / 100
    }
    return (gogc * start_heap.derate_hi_pct) / 100
}

func adjust_starting_heap(int requested_heap_goal, int derate_break, int derate_lo_pct, int derate_hi_pct, bool log_heap_tweaks) start_heap_state {
    if requested_heap_goal <= 0 {
        return start_heap
    }

    start_heap.requested_heap_goal = requested_heap_goal
    if derate_break > 0 {
        start_heap.derate_break = derate_break
    }
    if derate_lo_pct > 0 {
        start_heap.derate_lo_pct = derate_lo_pct
    }
    if derate_hi_pct > 0 {
        start_heap.derate_hi_pct = derate_hi_pct
    }
    start_heap.log_heap_tweaks = log_heap_tweaks

    let current_goal = 4 * 1000 * 1000
    let want_gogc = (100 * requested_heap_goal) / current_goal
    want_gogc = gogc_derate(want_gogc)
    if want_gogc <= 125 {
        start_heap.active = false
        return start_heap
    }

    start_heap.original_gogc = 100
    start_heap.current_gogc = want_gogc
    start_heap.active = true
    start_heap
}

func start_heap_done() bool {
    !start_heap.active
}
