// ============================================================
// mgc.s — S 运行时垃圾回收器（Stop-The-World 三色标记清除）
//
// 整体流程：
//   1. gc_trigger()   — 检查是否到达触发阈值
//   2. run_gc()       — 执行完整 GC 周期：
//      a. STW pause 开始
//      b. mark_init()    — 重置标记状态
//      c. mark_roots()   — 标记根集合
//      d. drain_mark_queue() — 排空灰色队列
//      e. sweep_pass()   — 清除白色对象
//      f. 更新 heap_goal_bytes
//      g. STW pause 结束
//
// 引用：
//   mgcmark.s   — 标记阶段实现
//   mgcsweep.s  — 清除阶段实现
//   malloc.s    — 堆状态全局变量
// ============================================================
package src.runtime

use std.vec.vec

// ─── GC 阶段常量 ──────────────────────────────────────────────
const GC_PHASE_OFF   = 0  // 未运行
const GC_PHASE_MARK  = 1  // 标记阶段
const GC_PHASE_SWEEP = 2  // 清除阶段

// ─── GC 全局状态 ──────────────────────────────────────────────
var gc_phase        = GC_PHASE_OFF
var gc_run_count    = 0
var gc_total_freed  = 0   // 累计释放字节
var gc_enabled      = true

// ─── OS 停止世界桥接 ──────────────────────────────────────────
// 暂停/恢复所有 goroutine（在协程调度器中实现）
extern "intrinsic" func __gc_stw_start() ()
extern "intrinsic" func __gc_stw_stop() ()

// 纳秒级时间戳（用于 pause 统计）
extern "intrinsic" func __runtime_nanotime() int

// ─── 主触发入口（分配路径调用）────────────────────────────────
// 若 heap_alloc_bytes ≥ heap_goal_bytes 则触发 GC
func gc_trigger() () {
    if !gc_enabled {
        return
    }
    if heap_alloc_bytes < heap_goal_bytes {
        return
    }
    run_gc()
}

// ─── 完整 GC 周期 ─────────────────────────────────────────────
func run_gc() () {
    if gc_phase != GC_PHASE_OFF {
        return  // GC 已在运行（防重入）
    }

    let t0 = __runtime_nanotime()

    // 1. 停止世界
    __gc_stw_start()

    // 2. 标记阶段
    gc_phase = GC_PHASE_MARK
    mark_init()
    mark_roots()
    drain_mark_queue()

    // 3. 清除阶段
    gc_phase = GC_PHASE_SWEEP
    let freed = sweep_pass()
    gc_total_freed = gc_total_freed + freed

    // 4. 更新统计
    gc_run_count = gc_run_count + 1
    gc_phase     = GC_PHASE_OFF

    // 5. 调整下次触发阈值（目标：当前存活量 × 2，最低 4 MB）
    heap_goal_bytes = heap_alloc_bytes * 2
    if heap_goal_bytes < 4194304 {
        heap_goal_bytes = 4194304
    }

    // 6. 恢复世界
    __gc_stw_stop()
}

// ─── 手动触发（供调试 / runtime.GC() 等价接口使用）──────────
func force_gc() () {
    run_gc()
}

// ─── GC 统计快照 ─────────────────────────────────────────────
struct GcStats {
    int phase           // 当前阶段
    int heap_alloc      // 已分配字节
    int heap_goal       // 下次 GC 阈值
    int num_gc          // GC 执行次数
    int total_freed     // 累计释放字节
    int live_objects    // 当前存活对象数
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

// ─── 控制接口 ─────────────────────────────────────────────────
func gc_disable() () { gc_enabled = false }
func gc_enable()  () { gc_enabled = true  }

func mgc_unit_name() string { "src/runtime/mgc" }
func mgc_unit_ready() int   { 1 }
