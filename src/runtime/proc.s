package src.runtime

use std.vec.vec

const G_IDLE     = 0
const G_RUNNABLE = 1
const G_RUNNING  = 2
const G_WAITING  = 3
const G_DEAD     = 4

struct G {
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
    int    cur_g
    vec[int] local_q
    int    local_head
    int    local_tail
}

struct M {
    int id
    int p_id
    int cur_g
    bool spinning
}

struct Scheduler {
    vec[G]   gs
    vec[M]   ms
    vec[P]   ps
    vec[int] global_q
    int      next_gid
    int      next_mid
    int      num_p
    Mutex    mu
}

var _sched = init_scheduler()

func init_scheduler() Scheduler {
    Scheduler {
        gs:        vec[G](),
        ms:        vec[M](),
        ps:        vec[P](),
        global_q:  vec[int](),
        next_gid:  1,
        next_mid:  1,
        num_p:     __runtime_num_cpu(),
        mu:        new_mutex(),
    }
}

extern "intrinsic" func __runtime_num_cpu() int
extern "intrinsic" func __os_thread_create(int m_id) int
extern "intrinsic" func __goroutine_switch(int from_g_id, int to_g_id) ()
extern "intrinsic" func __goroutine_init_stack(int g_id, func fn, int stack_size) ()
extern "intrinsic" func __goroutine_exit(int g_id) ()
extern "intrinsic" func __goroutine_current_id() int
extern "intrinsic" func __runtime_nanotime() int

func goroutine_spawn(func fn, string name) int {
    _sched.mu.lock()

    let gid = _sched.next_gid
    _sched.next_gid = _sched.next_gid + 1

    let g = G {
        id:         gid,
        status:     G_RUNNABLE,
        name:       name,
        parent_id:  __goroutine_current_id(),
        m_id:       -1,
        wait_for:   0,
        stack_size: 8192,
        system:     false,
    }

    _sched.gs.push(g)
    __goroutine_init_stack(gid, fn, 8192)
    _sched.global_q.push(gid)

    _sched.mu.unlock()

    try_wakeup_idle_m()

    gid
}

func gosched() () {
    let cur = __goroutine_current_id()
    if cur < 0 { return }

    _sched.mu.lock()
    set_g_status(cur, G_RUNNABLE)
    _sched.global_q.push(cur)
    _sched.mu.unlock()

    schedule()
}

func gopark(int reason) () {
    let cur = __goroutine_current_id()
    if cur < 0 { return }

    _sched.mu.lock()
    set_g_status(cur, G_WAITING)
    _sched.mu.unlock()

    schedule()
}

func goready(int gid) () {
    _sched.mu.lock()
    set_g_status(gid, G_RUNNABLE)
    _sched.global_q.push(gid)
    _sched.mu.unlock()

    try_wakeup_idle_m()
}

func schedule() () {
    let next_gid = find_runnable()
    if next_gid < 0 {
        m_idle()
        return
    }
    run_goroutine(next_gid)
}

func find_runnable() int {
    _sched.mu.lock()

    if !_sched.global_q.is_empty() {
        let gid = _sched.global_q.get(0).unwrap_or(-1)
        if gid >= 0 {
            _sched.global_q.set(0, -1)
            _sched.mu.unlock()
            return gid
        }
    }

    _sched.mu.unlock()
    -1
}

func run_goroutine(int gid) () {
    let cur = __goroutine_current_id()
    set_g_status(gid, G_RUNNING)
    __goroutine_switch(cur, gid)
}

func m_idle() () {
    let i = 0
    while i < 100 {
        let next = find_runnable()
        if next >= 0 {
            run_goroutine(next)
            return
        }
        i = i + 1
    }
    __os_thread_sleep_briefly()
}

extern "intrinsic" func __os_thread_sleep_briefly() ()

func try_wakeup_idle_m() () {
    if _sched.global_q.len() > 0 {
        let mid = _sched.next_mid
        _sched.next_mid = _sched.next_mid + 1
        let m = M { id: mid, p_id: -1, cur_g: -1, spinning: false }
        _sched.ms.push(m)
        __os_thread_create(mid)
    }
}

func set_g_status(int gid, int status) () {
    let i = 0
    while i < _sched.gs.len() {
        let g_opt = _sched.gs.get(i)
        switch g_opt {
            option::some(g) : {
                if g.id == gid {
                    let updated = G {
                        id:         g.id,
                        status:     status,
                        name:       g.name,
                        parent_id:  g.parent_id,
                        m_id:       g.m_id,
                        wait_for:   g.wait_for,
                        stack_size: g.stack_size,
                        system:     g.system,
                    }
                    _sched.gs.set(i, updated)
                    return
                }
            },
            option::none : (),
        }
        i = i + 1
    }
}

func num_goroutine() int {
    _sched.gs.len()
}

struct GoroutineInfo {
    int    id
    int    status
    string name
}

func goroutine_list() vec[GoroutineInfo] {
    let result = vec[GoroutineInfo]()
    let i = 0
    while i < _sched.gs.len() {
        let g_opt = _sched.gs.get(i)
        switch g_opt {
            option::some(g) : {
                result.push(GoroutineInfo {
                    id:     g.id,
                    status: g.status,
                    name:   g.name,
                })
            },
            option::none : (),
        }
        i = i + 1
    }
    result
}

func runtime_init() () {
    let num = __runtime_num_cpu()
    let i = 0
    while i < num {
        let p = P {
            id:         i,
            cur_g:      -1,
            local_q:    vec[int](),
            local_head: 0,
            local_tail: 0,
        }
        _sched.ps.push(p)
        i = i + 1
    }
    let m0 = M { id: 0, p_id: 0, cur_g: -1, spinning: false }
    _sched.ms.push(m0)
}

func proc_unit_name() string { "src/runtime/proc" }
func proc_unit_ready() int   { 1 }
