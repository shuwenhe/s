package src.runtime
use std.slices
const GC_WHITE = 0
const GC_GRAY  = 1
const GC_BLACK = 2
extern "intrinsic" func __gc_scan_roots(int[] out_roots) ()
extern "intrinsic" func __gc_get_children(int obj_id) int[]
extern "intrinsic" func __gc_cas_mark(int obj_id, int expected, int new_val) bool
var mark_gray_queue  = int[]()
var mark_total_count = 0
var mark_root_count  = 0

func mark_init() () {
    mark_gray_queue  = int[]()
    mark_total_count = 0
    mark_root_count  = 0
}

func mark_object(int obj_id) bool {
    if obj_id < 0 {
        return false
    }
    __gc_cas_mark(obj_id, GC_WHITE, GC_GRAY)
}

func mark_roots() () {
    roots := int[]()
    __gc_scan_roots(roots)
    i := 0
    for i < len(roots) {
        root_id := roots.get(i).unwrap_or(-1)
        if root_id >= 0 {
            if mark_object(root_id) {
                mark_gray_queue = append(mark_gray_queue, root_id)
                mark_root_count = mark_root_count + 1
            }
        }
        i = i + 1
    }
}

func drain_mark_queue() () {
    for !mark_gray_queue.is_empty() {
        obj_opt := mark_gray_queue.pop()
        obj_id := switch obj_opt {
            option::some(id) : id,
            option::none     : break,
        }
        children := __gc_get_children(obj_id)
        j := 0
        for j < len(children) {
            child_id := children.get(j).unwrap_or(-1)
            if child_id >= 0 {
                if mark_object(child_id) {
                    mark_gray_queue = append(mark_gray_queue, child_id)
                }
            }
            j = j + 1
        }
        __gc_cas_mark(obj_id, GC_GRAY, GC_BLACK)
        mark_total_count = mark_total_count + 1
    }
}

func write_barrier(int dst_obj_id, int src_obj_id) () {
    if src_obj_id >= 0 {
        if mark_object(src_obj_id) {
            mark_gray_queue = append(mark_gray_queue, src_obj_id)
        }
    }
}

func mgcmark_unit_name() string { "src/runtime/mgcmark" }

func mgcmark_unit_ready() int   { 1 }
