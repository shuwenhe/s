// ============================================================
// mgcsweep.s — GC 清除阶段
//
// 清除算法：
//   遍历堆中所有对象，对标记为白色（mark == 0）的对象
//   调用 free_obj() 释放；对黑色对象则重置为白色，
//   为下一轮 GC 做准备。
// ============================================================
package src.runtime

use std.vec.vec

// ─── 运行时桥接 ───────────────────────────────────────────────
extern "intrinsic" func __mem_heap_list_all() vec[int]
extern "intrinsic" func __mem_obj_read_header(int obj_id) ObjHeader
extern "intrinsic" func __mem_obj_set_mark(int obj_id, int mark) ()
extern "intrinsic" func __mem_os_free(int obj_id) ()

// ─── 清除统计 ─────────────────────────────────────────────────
var sweep_freed_bytes = 0
var sweep_freed_count = 0
var sweep_live_count  = 0

// ─── 单次清除遍历 ─────────────────────────────────────────────
// 返回本次释放的字节数
func sweep_pass() int {
    sweep_freed_bytes = 0
    sweep_freed_count = 0
    sweep_live_count  = 0

    let all_objs = __mem_heap_list_all()
    let i = 0
    while i < all_objs.len() {
        let obj_id = all_objs.get(i).unwrap_or(-1)
        if obj_id >= 0 {
            let hdr = __mem_obj_read_header(obj_id)
            if hdr.mark == GC_WHITE {
                // 白色 = 未被标记 = 垃圾，释放
                sweep_freed_bytes = sweep_freed_bytes + hdr.size
                sweep_freed_count = sweep_freed_count + 1
                // 更新全局堆计数
                heap_alloc_bytes = heap_alloc_bytes - hdr.size
                if heap_alloc_bytes < 0 {
                    heap_alloc_bytes = 0
                }
                heap_live_objs = heap_live_objs - 1
                if heap_live_objs < 0 {
                    heap_live_objs = 0
                }
                heap_dead_objs = heap_dead_objs + 1
                __mem_os_free(obj_id)
            } else {
                // 黑色/灰色 = 存活，重置为白色备下轮
                __mem_obj_set_mark(obj_id, GC_WHITE)
                sweep_live_count = sweep_live_count + 1
            }
        }
        i = i + 1
    }

    sweep_freed_bytes
}

// ─── 清除统计快照 ─────────────────────────────────────────────
func sweep_stats() sweep_result {
    sweep_result {
        freed_bytes: sweep_freed_bytes,
        freed_count: sweep_freed_count,
        live_count:  sweep_live_count,
    }
}

struct sweep_result {
    int freed_bytes
    int freed_count
    int live_count
}

func mgcsweep_unit_name() string { "src/runtime/mgcsweep" }
func mgcsweep_unit_ready() int   { 1 }
