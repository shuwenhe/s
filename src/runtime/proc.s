// ============================================================
// proc.s — S 运行时协程调度器（M:N 模型）
//
// 核心概念（类比 Go runtime）：
//   G  — goroutine：用户级轻量协程，含栈、状态、函数
//   M  — machine：OS 线程；执行 G
//   P  — processor：执行上下文；持有本地运行队列
//
// 当前实现：
//   • 全局运行队列（GRQ）+ 工作窃取
//   • 协作式调度（函数调用边界 yield）
//   • 抢占信号通过 SIGURG 注入（由 OS 层实现）
//   • goroutine 状态机：Idle → Runnable → Running → Dead/Waiting
// ============================================================
package src.runtime

use std.vec.vec

// ─── G 状态 ───────────────────────────────────────────────────
const G_IDLE     = 0  // 刚创建，未入队
const G_RUNNABLE = 1  // 就绪，等待调度
const G_RUNNING  = 2  // 正在执行
const G_WAITING  = 3  // 阻塞（channel/锁/sleep）
const G_DEAD     = 4  // 已完成

// ─── Goroutine 结构 ───────────────────────────────────────────
struct G {
    int    id
    int    status
    string name      // 调试用途
    int    parent_id // 创建者的 G id
    int    m_id      // 当前执行的 M（-1 = 未绑定）
    int    wait_for  // 阻塞原因代码（0 = 无）
    int    stack_size // 栈大小（字节）
    bool   system    // 是否为运行时系统 goroutine
}

// ─── P（Processor）结构 ──────────────────────────────────────
struct P {
    int    id
    int    cur_g      // 当前运行的 G id（-1 = 空闲）
    vec[int] local_q  // 本地运行队列（环形，最多 256 个）
    int    local_head
    int    local_tail
}

// ─── M（Machine/OS Thread）结构 ─────────────────────────────
struct M {
    int id
    int p_id    // 绑定的 P（-1 = 无）
    int cur_g   // 当前运行的 G id
    bool spinning  // 是否在窃取工作
}

// ─── 全局调度器 ───────────────────────────────────────────────
struct Scheduler {
    vec[G]   gs        // 所有 goroutine 表
    vec[M]   ms        // 所有 M 表
    vec[P]   ps        // 所有 P 表
    vec[int] global_q  // 全局运行队列
    int      next_gid  // 下一个 G ID
    int      next_mid  // 下一个 M ID
    int      num_p     // P 的数量（≈ GOMAXPROCS）
    Mutex    mu        // 全局调度器锁
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

// ─── OS 桥接 ──────────────────────────────────────────────────
// 获取 CPU 核心数
extern "intrinsic" func __runtime_num_cpu() int
// 创建 OS 线程并运行函数
extern "intrinsic" func __os_thread_create(int m_id) int
// 切换到 goroutine 上下文（保存当前，恢复目标）
extern "intrinsic" func __goroutine_switch(int from_g_id, int to_g_id) ()
// 初始化新 goroutine 栈帧
extern "intrinsic" func __goroutine_init_stack(int g_id, func fn, int stack_size) ()
// 结束当前 goroutine
extern "intrinsic" func __goroutine_exit(int g_id) ()
// 获取当前 goroutine ID
extern "intrinsic" func __goroutine_current_id() int
// 高精度计时器
extern "intrinsic" func __runtime_nanotime() int

// ─── 创建新 Goroutine ─────────────────────────────────────────
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
        stack_size: 8192,   // 初始栈 8 KB（可增长）
        system:     false,
    }

    _sched.gs.push(g)
    __goroutine_init_stack(gid, fn, 8192)
    _sched.global_q.push(gid)

    _sched.mu.unlock()

    // 尝试唤醒空闲 M
    try_wakeup_idle_m()

    gid
}

// ─── 让出执行权（协作式 yield）────────────────────────────────
func gosched() () {
    let cur = __goroutine_current_id()
    if cur < 0 { return }

    _sched.mu.lock()
    set_g_status(cur, G_RUNNABLE)
    _sched.global_q.push(cur)
    _sched.mu.unlock()

    schedule()
}

// ─── 挂起当前 goroutine（等待某事件）────────────────────────
func gopark(int reason) () {
    let cur = __goroutine_current_id()
    if cur < 0 { return }

    _sched.mu.lock()
    set_g_status(cur, G_WAITING)
    _sched.mu.unlock()

    schedule()
}

// ─── 就绪化（唤醒）一个 goroutine ──────────────────────────
func goready(int gid) () {
    _sched.mu.lock()
    set_g_status(gid, G_RUNNABLE)
    _sched.global_q.push(gid)
    _sched.mu.unlock()

    try_wakeup_idle_m()
}

// ─── 主调度循环 ───────────────────────────────────────────────
func schedule() () {
    let next_gid = find_runnable()
    if next_gid < 0 {
        // 无可运行 goroutine，该 M 变为空闲
        m_idle()
        return
    }
    run_goroutine(next_gid)
}

func find_runnable() int {
    _sched.mu.lock()

    // 优先从全局队列取
    if !_sched.global_q.is_empty() {
        let gid = _sched.global_q.get(0).unwrap_or(-1)
        if gid >= 0 {
            _sched.global_q.set(0, -1)
            // TODO: 高效的 dequeue — 当前简化为线性移位
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

// ─── M 空闲处理 ───────────────────────────────────────────────
func m_idle() () {
    // 简单实现：自旋等待或 OS 睡眠
    let i = 0
    while i < 100 {
        let next = find_runnable()
        if next >= 0 {
            run_goroutine(next)
            return
        }
        i = i + 1
    }
    // 超过自旋次数，OS 睡眠（由下层实现）
    __os_thread_sleep_briefly()
}

extern "intrinsic" func __os_thread_sleep_briefly() ()

// ─── 唤醒空闲 M ─────────────────────────────────────────────
func try_wakeup_idle_m() () {
    // 简化：直接让运行时决定是否需要新线程
    if _sched.global_q.len() > 0 {
        let mid = _sched.next_mid
        _sched.next_mid = _sched.next_mid + 1
        let m = M { id: mid, p_id: -1, cur_g: -1, spinning: false }
        _sched.ms.push(m)
        __os_thread_create(mid)
    }
}

// ─── 辅助：设置 G 状态 ───────────────────────────────────────
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

// ─── 公开：goroutine 数量 ─────────────────────────────────────
func num_goroutine() int {
    _sched.gs.len()
}

// ─── goroutine 信息快照 ───────────────────────────────────────
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

// ─── runtime 初始化入口 ──────────────────────────────────────
func runtime_init() () {
    // 启动与 CPU 数相等的 P
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
    // 创建初始 M（main thread 的 M）
    let m0 = M { id: 0, p_id: 0, cur_g: -1, spinning: false }
    _sched.ms.push(m0)
}

func proc_unit_name() string { "src/runtime/proc" }
func proc_unit_ready() int   { 1 }
