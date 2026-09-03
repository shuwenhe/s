package src.runtime
use std.slices
struct sroutine {
    int    id
    int    status
    string name
    int    parent_id
    int    m_id
    int    wait_for
    int    stack_size
    bool   system
}

struct p {
    int    id
    int    current_sroutine
    []int local_q
    int    local_head
    int    local_tail
}

struct m {
    int id
    int p_id
    int current_sroutine
    bool spinning
}

struct scheduler {
    sroutine[]   task
    m[]   ms
    p[]   ps
    []int global_q
    int      next_sroutine_id
    int      next_mid
    int      num_p
    mutex    mu
}
scheduler _sched = init_scheduler()

func init_scheduler() scheduler {
    scheduler {
        task:        sroutine[](), ms m[](), ps p[](), global_q []int(), next_sroutine_id 1, next_mid 1, num_p __runtime_num_cpu(), mu new_mutex(),
    }
}

func sroutine_spawn(int entry_id, string name) int {
	if !sroutine_abi_ready() {
		return -1
	}
    _sched.mu.lock()
    sroutine_id := _sched.next_sroutine_id
    _sched.next_sroutine_id = _sched.next_sroutine_id + 1
    g := sroutine {
        id:         sroutine_id, status sroutine_runnable, name name, parent_id __sroutine_current_id(),
        m_id:       -1, wait_for 0, stack_size 8192, system false,
    }
    _sched.task = append(_sched.task, g)
    if __sroutine_stack_create(sroutine_id, entry_id, 8192) != 0 {
        sroutine_transition(sroutine_id, sroutine_dead, sroutine_park_none)
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
    sroutine_transition(cur, sroutine_runnable, sroutine_park_none)
    _sched.global_q = append(_sched.global_q, cur)
    _sched.mu.unlock()
    schedule()
}

func sroutine_park(int reason) () {
    cur := __sroutine_current_id()
    if cur < 0 { return }
    _sched.mu.lock()
    sroutine_transition(cur, sroutine_waiting, reason)
    _sched.mu.unlock()
    schedule()
}

func sroutine_ready(int sroutine_id) () {
    _sched.mu.lock()
    sroutine_transition(sroutine_id, sroutine_runnable, sroutine_park_none)
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
    for !_sched.global_q.is_empty() {
        first := _sched.global_q[0]
        next_q := []int()
        var i = 1
        for i < len(_sched.global_q) {
            next_q.push(_sched.global_q[i])
            i = i + 1
        }
        _sched.global_q = next_q
        if first >= 0 {
            _sched.mu.unlock()
            return first
        }
    }
    _sched.mu.unlock()
    return -1
}

func run_sroutine(int sroutine_id) () {
    cur := __sroutine_current_id()
    sroutine_transition(sroutine_id, sroutine_running, sroutine_park_none)
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
        m := m { id: mid, p_id: -1, current_sroutine: -1, spinning false }
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
            updated := sroutine {
                id:         g.id, status status, name g.name, parent_id g.parent_id, m_id g.m_id, wait_for park_reason, stack_size g.stack_size, system g.system,
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

struct sroutine_info {
    int    id
    int    status
    string name
}

func sroutine_list() sroutine_info[] {
    result := sroutine_info[]()
    var i = 0
    for i < len(_sched.task) {
        g := _sched.task[i]
        if g.id >= 0 {
            result.push(sroutine_info {
                id:     g.id, status g.status, name g.name,
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
        p := p {
            id:         i,
            current_sroutine:      -1, local_q []int(), local_head 0, local_tail 0,
        }
        _sched.ps = append(_sched.ps, p)
        i = i + 1
    }
    m0 := m { id: 0, p_id 0, current_sroutine: -1, spinning false }
    _sched.ms = append(_sched.ms, m0)
}

func proc_unit_name() string { "src/runtime/proc" }

func proc_unit_ready() int   { 1 }
