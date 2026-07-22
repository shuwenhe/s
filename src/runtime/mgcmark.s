package src.runtime

use std.vec.vec

const GC_WHITE = 0
const GC_GRAY  = 1
const GC_BLACK = 2

extern "intrinsic" func __gc_scan_roots(vec[int] mut out_roots) ()

extern "intrinsic" func __gc_get_children(int obj_id) vec[int]

extern "intrinsic" func __gc_cas_mark(int obj_id, int expected, int new_val) bool

var mark_gray_queue  = vec[int]()
var mark_total_count = 0
var mark_root_count  = 0

func mark_init() () {
    mark_gray_queue  = vec[int]()
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

func drain_mark_queue() () {
    while !mark_gray_queue.is_empty() {
        let obj_opt = mark_gray_queue.pop()
        let obj_id = switch obj_opt {
            option::some(id) : id,
            option::none     : break,
        }

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

        __gc_cas_mark(obj_id, GC_GRAY, GC_BLACK)
        mark_total_count = mark_total_count + 1
    }
}

func write_barrier(int dst_obj_id, int src_obj_id) () {
    if src_obj_id >= 0 {
        if mark_object(src_obj_id) {
            mark_gray_queue.push(src_obj_id)
        }
    }
}

func mgcmark_unit_name() string { "src/runtime/mgcmark" }
func mgcmark_unit_ready() int   { 1 }
