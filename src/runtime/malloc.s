package src.runtime

use std.vec.vec
use std.result.result

struct ObjHeader {
    int size
    int type_id
    int mark
    int next_free
}

const NUM_SIZE_CLASSES = 68
const MAX_SMALL_SIZE   = 32768
const MIN_ALLOC        = 8

var heap_alloc_bytes = 0
var heap_sys_bytes   = 0
var heap_live_objs   = 0
var heap_dead_objs   = 0
var heap_goal_bytes  = 4194304

extern "intrinsic" func __mem_os_alloc(int size_bytes) int
extern "intrinsic" func __mem_os_free(int obj_id) ()
extern "intrinsic" func __mem_obj_write_header(int obj_id, ObjHeader h) ()
extern "intrinsic" func __mem_obj_read_header(int obj_id) ObjHeader
extern "intrinsic" func __mem_obj_set_mark(int obj_id, int mark) ()
extern "intrinsic" func __mem_obj_get_mark(int obj_id) int
extern "intrinsic" func __mem_heap_list_all() vec[int]
extern "intrinsic" func __mem_size_class(int size) int

func malloc(int size, int type_id) int {
    if size <= 0 {
        return -1
    }
    let actual_size = if size <= MAX_SMALL_SIZE {
        __mem_size_class(size)
    } else {
        size
    }

    let obj_id = __mem_os_alloc(actual_size)
    if obj_id < 0 {
        return -1
    }

    __mem_obj_write_header(obj_id, ObjHeader {
        size:      actual_size,
        type_id:   type_id,
        mark:      0,
        next_free: -1,
    })

    heap_alloc_bytes = heap_alloc_bytes + actual_size
    heap_live_objs   = heap_live_objs + 1

    obj_id
}

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

func heap_all_objects() vec[int] {
    __mem_heap_list_all()
}

func malloc_unit_name() string { "src/runtime/malloc" }
func malloc_unit_ready() int   { 1 }
