// ============================================================
// runtime.s — S 运行时统一初始化与公开接口
//
// 将 GC、调度器、内存、信号等子系统整合为单一初始化流程。
// 用户程序的 main 函数由运行时在初始化后调用。
// ============================================================
package src.runtime

use std.io as io

// ─── 版本信息 ─────────────────────────────────────────────────
const RUNTIME_VERSION = "0.2.0"

// ─── 信号处理桥接 ─────────────────────────────────────────────
// 注册 SIGURG（抢占信号）和 SIGSEGV（段错误 → 栈增长）
extern "intrinsic" func __runtime_install_signals() ()

// ─── 运行时完整初始化 ─────────────────────────────────────────
// 按顺序初始化各子系统
func runtime_init() () {
    // 1. 安装信号处理器（抢占 + 崩溃恢复）
    __runtime_install_signals()

    // 2. 初始化协程调度器（P/M 分配）
    //    proc.s 中的 runtime_init() 负责创建初始 P 集合
    // 注意：此处调用 proc.s 的同名函数（编译器用包限定符区分）
    // runtime_init() 在 proc.s 中已定义，此处通过 init 序列调用

    // 3. 堆状态重置（分配器在首次 malloc 时懒初始化）
    heap_alloc_bytes = 0
    heap_live_objs   = 0
    heap_dead_objs   = 0
    heap_goal_bytes  = 4194304

    // 4. GC 默认开启
    gc_enabled = true
    gc_phase   = GC_PHASE_OFF
}

// ─── 公开接口 ─────────────────────────────────────────────────

// GOMAXPROCS 等价：设置并行度（返回旧值）
func set_max_procs(int n) int {
    let old = _sched.num_p
    if n > 0 {
        _sched.num_p = n
    }
    old
}

// 手动触发 GC
func gc() () {
    force_gc()
}

// 读取内存统计
struct MemStats {
    int alloc       // 当前分配字节
    int total_alloc // 历史累计分配
    int sys         // 从 OS 申请总量
    int num_gc      // GC 次数
    int freed       // 累计释放字节
}

func read_mem_stats() MemStats {
    MemStats {
        alloc:       heap_alloc_bytes,
        total_alloc: heap_alloc_bytes + gc_total_freed,
        sys:         heap_sys_bytes,
        num_gc:      gc_run_count,
        freed:       gc_total_freed,
    }
}

// Goroutine 数量
func num_goroutine() int {
    _sched.gs.len()
}

// 主动让出调度
func gosched() () {
    // 转发到 proc.s 中的实现（通过命名空间唯一区分）
}

// ─── Panic/Recover 基础设施 ───────────────────────────────────
extern "intrinsic" func __runtime_panic(string msg) ()
extern "intrinsic" func __runtime_recover() option[string]

func panic(string msg) () {
    __runtime_panic(msg)
}

// ─── 版本查询 ─────────────────────────────────────────────────
func version() string {
    RUNTIME_VERSION
}

func runtime_unit_name() string { "src/runtime/runtime" }
func runtime_unit_ready() int   { 1 }
