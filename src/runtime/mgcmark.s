// ============================================================
// mgcmark.s — GC 标记阶段（三色标记）
//
// 标记算法：
//   1. 从根集合（全局变量 + 所有 G 的栈帧）出发，
//      将直接引用的对象染灰（加入灰色队列）。
//   2. 逐步处理灰色队列：对每个灰色对象，
//      扫描其内部指针，将未标记的子对象染灰，
//      然后将该对象染黑。
//   3. 队列耗尽后，所有剩余白色对象为垃圾。
// ============================================================
package src.runtime

use std.vec.vec

// ─── 颜色常量 ─────────────────────────────────────────────────
const GC_WHITE = 0   // 未标记（待回收候选）
const GC_GRAY  = 1   // 已标记，子对象未处理
const GC_BLACK = 2   // 已标记，子对象已处理

// ─── 运行时桥接：根集合 + 类型元数据 ─────────────────────────
// 扫描根集合（全局变量 + 所有协程栈），填充 out_roots
extern "intrinsic" func __gc_scan_roots(vec[int] mut out_roots) ()

// 获取对象内所有指针子对象的 obj_id 列表
extern "intrinsic" func __gc_get_children(int obj_id) vec[int]

// 原子性读/写对象标记位（支持并发标记扩展）
extern "intrinsic" func __gc_cas_mark(int obj_id, int expected, int new_val) bool

// ─── 标记状态（被 mgc.s 管理）────────────────────────────────
var mark_gray_queue  = vec[int]()  // 灰色工作队列
var mark_total_count = 0           // 本轮标记对象总数
var mark_root_count  = 0           // 根对象数量

// ─── 初始化：重置标记状态 ─────────────────────────────────────
func mark_init() () {
    mark_gray_queue  = vec[int]()
    mark_total_count = 0
    mark_root_count  = 0
}

// ─── 标记单个对象（白 → 灰）──────────────────────────────────
// 返回 true 表示首次标记（对象原来是白色）
func mark_object(int obj_id) bool {
    if obj_id < 0 {
        return false
    }
    // CAS：白(0) → 灰(1)；若已是灰/黑则直接返回 false
    __gc_cas_mark(obj_id, GC_WHITE, GC_GRAY)
}

// ─── 标记根集合（启动标记阶段的第一步）───────────────────────
func mark_roots() () {
    let roots = vec[int]()
    __gc_scan_roots(roots)

    let i = 0
    while i < roots.len() {
        let root_id = roots.get(i).unwrap_or(-1)
        if root_id >= 0 {
            if mark_object(root_id) {
                mark_gray_queue.push(root_id)
                mark_root_count = mark_root_count + 1
            }
        }
        i = i + 1
    }
}

// ─── 排空灰色队列（标记阶段主循环）──────────────────────────
func drain_mark_queue() () {
    while !mark_gray_queue.is_empty() {
        let obj_opt = mark_gray_queue.pop()
        let obj_id = switch obj_opt {
            option::some(id) : id,
            option::none     : break,
        }

        // 扫描子指针
        let children = __gc_get_children(obj_id)
        let j = 0
        while j < children.len() {
            let child_id = children.get(j).unwrap_or(-1)
            if child_id >= 0 {
                if mark_object(child_id) {
                    mark_gray_queue.push(child_id)
                }
            }
            j = j + 1
        }

        // 灰 → 黑
        __gc_cas_mark(obj_id, GC_GRAY, GC_BLACK)
        mark_total_count = mark_total_count + 1
    }
}

// ─── 写屏障（并发 GC 扩展用）──────────────────────────────────
// 当程序写入指针字段时调用，确保新指针不被漏标。
// 在当前停止世界模式下为空操作；并发模式需激活。
func write_barrier(int dst_obj_id, int src_obj_id) () {
    // Dijkstra 写屏障：若 src 是白色则染灰
    if src_obj_id >= 0 {
        if mark_object(src_obj_id) {
            mark_gray_queue.push(src_obj_id)
        }
    }
}

func mgcmark_unit_name() string { "src/runtime/mgcmark" }
func mgcmark_unit_ready() int   { 1 }
