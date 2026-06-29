// ============================================================
// malloc.s — S 运行时堆分配器
//
// 设计：
//   • 分级空闲链表（size classes）处理小对象（≤ 32 KB）
//   • 超过 32 KB 的大对象直接向 OS 申请
//   • 每次分配都写入 ObjHeader（含大小、类型、标记位）
//   • 与 GC（mgc.s）协作：分配时增加 heap_alloc_bytes，
//     触发 GC 后由 mgcsweep.s 更新统计
// ============================================================
package src.runtime

use std.vec.vec
use std.result.result

// ─── 对象头部（每个堆对象前置）────────────────────────────────
// 注意：S 是安全语言，对象头由运行时维护，对用户不可见。
// 以下结构反映运行时内部布局，通过 extern intrinsic 访问。
struct ObjHeader {
    int size        // 分配大小（字节）
    int type_id     // 类型 ID（用于 GC 追踪指针）
    int mark        // GC 颜色：0=白/未标记 1=灰/待处理 2=黑/已标记
    int next_free   // 空闲链表中的下一个（-1 = 无）
}

// ─── 大小等级表（对齐到 8 字节边界）──────────────────────────
// 共 68 个等级，覆盖 8 ~ 32768 字节
const NUM_SIZE_CLASSES = 68
const MAX_SMALL_SIZE   = 32768   // 32 KB
const MIN_ALLOC        = 8

// ─── 全局堆状态（由 GC 负责读写）─────────────────────────────
var heap_alloc_bytes = 0     // 当前已分配字节数（不含头部）
var heap_sys_bytes   = 0     // 从 OS 申请的总字节数
var heap_live_objs   = 0     // 当前存活对象数
var heap_dead_objs   = 0     // 上次 GC 释放对象数
var heap_goal_bytes  = 4194304  // 触发 GC 的阈值（初始 4 MB）

// ─── OS 内存分配原语（由运行时/OS 层实现）──────────────────────
extern "intrinsic" func __mem_os_alloc(int size_bytes) int        // 返回 obj_id（运行时句柄）
extern "intrinsic" func __mem_os_free(int obj_id) ()
extern "intrinsic" func __mem_obj_write_header(int obj_id, ObjHeader h) ()
extern "intrinsic" func __mem_obj_read_header(int obj_id) ObjHeader
extern "intrinsic" func __mem_obj_set_mark(int obj_id, int mark) ()
extern "intrinsic" func __mem_obj_get_mark(int obj_id) int
extern "intrinsic" func __mem_heap_list_all() vec[int]   // 返回所有存活 obj_id
extern "intrinsic" func __mem_size_class(int size) int   // 对齐到最近等级

// ─── 核心分配函数 ─────────────────────────────────────────────

// 分配 size 字节，关联 type_id（0 = 不含指针的原始数据）
// 返回运行时对象句柄（obj_id）。
func malloc(int size, int type_id) int {
    if size <= 0 {
        return -1
    }
    let actual_size = if size <= MAX_SMALL_SIZE {
        __mem_size_class(size)  // 对齐到大小等级
    } else {
        size  // 大对象：按实际大小分配
    }

    let obj_id = __mem_os_alloc(actual_size)
    if obj_id < 0 {
        return -1  // OOM
    }

    __mem_obj_write_header(obj_id, ObjHeader {
        size:      actual_size,
        type_id:   type_id,
        mark:      0,   // 白色：待 GC 检查
        next_free: -1,
    })

    heap_alloc_bytes = heap_alloc_bytes + actual_size
    heap_live_objs   = heap_live_objs + 1

    obj_id
}

// 释放对象（通常由 GC 调用，用户代码不应直接调用）
func free_obj(int obj_id) () {
    let hdr = __mem_obj_read_header(obj_id)
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
}

// ─── 查询接口 ─────────────────────────────────────────────────
func alloc_stats() malloc_stats {
    malloc_stats {
        alloc_bytes: heap_alloc_bytes,
        sys_bytes:   heap_sys_bytes,
        live_objs:   heap_live_objs,
        dead_objs:   heap_dead_objs,
        goal_bytes:  heap_goal_bytes,
    }
}

struct malloc_stats {
    int alloc_bytes
    int sys_bytes
    int live_objs
    int dead_objs
    int goal_bytes
}

// 返回所有堆对象 ID（供 GC 扫描）
func heap_all_objects() vec[int] {
    __mem_heap_list_all()
}

// 兼容桩
func malloc_unit_name() string { "src/runtime/malloc" }
func malloc_unit_ready() int   { 1 }
