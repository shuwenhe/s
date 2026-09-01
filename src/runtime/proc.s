package src.runtime
use std.slices
struct Sroutine {
    int    id
    int    status
    string name
    int    parent_id
    int    m_id
    int    wait_for
    int    stack_size
    bool   system
}

struct P {
    int    id
    int    current_sroutine
    int[] local_q
    int    local_head
    int    local_tail
}

struct M {
    int id
    int p_id
    int current_sroutine
    bool spinning
}

struct Scheduler {
    Sroutine[]   task
    M[]   ms
    P[]   ps
    int[] global_q
    int      next_sroutine_id
    int      next_mid
    int      num_p
    Mutex    mu
}
var _sched Scheduler = init_scheduler()

func init_scheduler() Scheduler {
    Scheduler {
        task:        Sroutine[](),
        ms:        M[](),
        ps:        P[](),
        global_q:  int[](),
        next_sroutine_id:  1,
        next_mid:  1,
        num_p:     __runtime_num_cpu(),
        mu:        new_mutex(),
    }
}

func sroutine_spawn(int entry_id, string name) int {
	if !sroutine_abi_ready() {
		return -1
	}
    _sched.mu.lock()
    sroutine_id := _sched.next_sroutine_id
    _sched.next_sroutine_id = _sched.next_sroutine_id + 1
    g := Sroutine {
        id:         sroutine_id,
        status:     SROUTINE_RUNNABLE,
        name:       name,
        parent_id:  __sroutine_current_id(),
        m_id:       -1,
        wait_for:   0,
        stack_size: 8192,
        system:     false,
    }
    _sched.task = append(_sched.task, g)
    if __sroutine_stack_create(sroutine_id, entry_id, 8192) != 0 {
        sroutine_transition(sroutine_id, SROUTINE_DEAD, SROUTINE_PARK_NONE)
        _sched.mu.unlock()
        return -1
    }
    _sched.global_q = append(_sched.global_q, sroutine_id)
    _sched.mu.unlock()
    try_wakeup_idle_m()
    sroutine_id
}

func sroutine_yield() () {
    cur := __sroutine_current_id()
    if cur < 0 { return }
    _sched.mu.lock()
    sroutine_transition(cur, SROUTINE_RUNNABLE, SROUTINE_PARK_NONE)
    _sched.global_q = append(_sched.global_q, cur)
    _sched.mu.unlock()
    schedule()
}

func sroutine_park(int reason) () {
    cur := __sroutine_current_id()
    if cur < 0 { return }
    _sched.mu.lock()
    sroutine_transition(cur, SROUTINE_WAITING, reason)
    _sched.mu.unlock()
    schedule()
}

func sroutine_ready(int sroutine_id) () {
    _sched.mu.lock()
    sroutine_transition(sroutine_id, SROUTINE_RUNNABLE, SROUTINE_PARK_NONE)
    _sched.global_q = append(_sched.global_q, sroutine_id)
    _sched.mu.unlock()
    try_wakeup_idle_m()
}

func schedule() () {
    next_sroutine_id := find_runnable()
    if next_sroutine_id < 0 {
        m_idle()
        return
    }
    run_sroutine(next_sroutine_id)
}

func find_runnable() int {
    _sched.mu.lock()
    if !_sched.global_q.is_empty() {
        sroutine_id := _sched.global_q[0]
        if sroutine_id >= 0 {
            _sched.global_q[0] = -1
            _sched.mu.unlock()
            return sroutine_id
        }
    }
    _sched.mu.unlock()
    return -1
}

func run_sroutine(int sroutine_id) () {
    cur := __sroutine_current_id()
    sroutine_transition(sroutine_id, SROUTINE_RUNNING, SROUTINE_PARK_NONE)
    __sroutine_context_switch(cur, sroutine_id)
}

func m_idle() () {
    var i = 0
    for i < 100 {
        next := find_runnable()
        if next >= 0 {
            run_sroutine(next)
            return
        }
        i = i + 1
    }
    __runtime_sleep_briefly()
}

func try_wakeup_idle_m() () {
    if len(_sched.global_q) > 0 {
        mid := _sched.next_mid
        _sched.next_mid = _sched.next_mid + 1
        m := M { id: mid, p_id: -1, current_sroutine: -1, spinning: false }
        _sched.ms = append(_sched.ms, m)
        __runtime_thread_wake(mid)
    }
}

func sroutine_transition(int sroutine_id, int status, int park_reason) bool {
    var i = 0
    for i < len(_sched.task) {
        g := _sched.task[i]
        if g.id == sroutine_id {
            if !sroutine_state_can_transition(g.status, status) {
                return false
            }
            updated := Sroutine {
                id:         g.id,
                status:     status,
                name:       g.name,
                parent_id:  g.parent_id,
                m_id:       g.m_id,
                wait_for:   park_reason,
                stack_size: g.stack_size,
                system:     g.system,
            }
            _sched.task[i] = updated
            return true
        }
        i = i + 1
    }
    false
}

func num_sroutine() int {
    len(_sched.task)
}

struct SroutineInfo {
    int    id
    int    status
    string name
}

func sroutine_list() SroutineInfo[] {
    result := SroutineInfo[]()
    var i = 0
    for i < len(_sched.task) {
        g := _sched.task[i]
        if g.id >= 0 {
            result.push(SroutineInfo {
                id:     g.id,
                status: g.status,
                name:   g.name,
            })
        }
        i = i + 1
    }
    result
}

func runtime_init() () {
    num := __runtime_num_cpu()
    var i = 0
    for i < num {
        p := P {
            id:         i,
            current_sroutine:      -1,
            local_q:    int[](),
            local_head: 0,
            local_tail: 0,
        }
        _sched.ps = append(_sched.ps, p)
        i = i + 1
    }
    m0 := M { id: 0, p_id: 0, current_sroutine: -1, spinning: false }
    _sched.ms = append(_sched.ms, m0)
}

func proc_unit_name() string { "src/runtime/proc" }

func proc_unit_ready() int   { 1 }
