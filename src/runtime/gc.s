package src.runtime

import (
	"src/sync"
	"src/unsafe"
)

enum gc_color {
	gc_white = 0
	gc_gray = 1
	gc_black = 2
}

enum gc_phase {
	gc_off = 0
	gc_mark = 1
	gc_mark_termination = 2
	gc_sweep = 3
}

struct gc_object {
	addr u64
	size u64
	color gc_color
	mark_bit u32
	alloc_tick u64
}

struct gc_heap {
	objects gc_object[]
	gray_queue u64[]
	total_alloc u64
	total_freed u64
	num_gc i32
	gc_phase gc_phase
	mark_bits u8[]
	barrier_buf u64[]
	lock sync.mutex
}

struct gc_stats {
	alloc_bytes u64
	freed_bytes u64
	num_collections i32
	mark_time_ns i64
	sweep_time_ns i64
	pause_ns i64[]
	heap_size u64
	live_objects i32
}

var global_heap gc_heap
var gc_stats_data gc_stats
var gc_roots u64[]
var gc_enabled bool

func gc_init() error {
	global_heap.objects = make(gc_object[], 0)
	global_heap.gray_queue = make(u64[], 0)
	global_heap.mark_bits = make(u8[], 1024)
	global_heap.barrier_buf = make(u64[], 0)
	gc_roots = make(u64[], 0)
	gc_enabled = true
	nil
}

func gc_malloc(size u64) (unsafe.pointer, error) {
	global_heap.lock.lock()
	defer global_heap.lock.unlock()

	if global_heap.total_alloc > 100*1024*1024 {
		gc_run()
	}

	addr := allocate_memory(size)
	if addr == 0 {
		nil, "allocation failed"
	}

	obj := gc_object{
		addr: addr,
		size: size,
		color: gc_white,
		alloc_tick: get_ticks(),
	}

	global_heap.objects = append(global_heap.objects, obj)
	global_heap.total_alloc += size

	unsafe.pointer(addr), nil
}

func gc_run() {
	if !gc_enabled {
		return
	}

	start := get_time_ns()

	gc_mark_phase()
	gc_mark_termination_phase()
	gc_sweep_phase()

	end := get_time_ns()
	gc_stats_data.pause_ns = append(gc_stats_data.pause_ns, end-start)
	gc_stats_data.num_collections += 1
}

func gc_mark_phase() {
	global_heap.gc_phase = gc_mark

	for _, root := range gc_roots {
		gc_mark_object(root)
	}

	for len(global_heap.gray_queue) > 0 {
		obj_addr := global_heap.gray_queue[0]
		global_heap.gray_queue = global_heap.gray_queue[1:]
		gc_process_object(obj_addr)
	}
}

func gc_mark_object(addr u64) {
	if addr == 0 {
		return
	}

	for i := i32(0); i < i32(len(global_heap.objects)); i += 1 {
		if global_heap.objects[i].addr == addr {
			if global_heap.objects[i].color == gc_white {
				global_heap.objects[i].color = gc_gray
				global_heap.gray_queue = append(global_heap.gray_queue, addr)
			}
			return
		}
	}
}

func gc_process_object(addr u64) {
	for i := i32(0); i < i32(len(global_heap.objects)); i += 1 {
		if global_heap.objects[i].addr == addr {
			if global_heap.objects[i].color == gc_gray {
				global_heap.objects[i].color = gc_black

				ptr := unsafe.pointer(addr)
				scan_object_for_pointers(ptr, global_heap.objects[i].size)
			}
			return
		}
	}
}

func scan_object_for_pointers(obj unsafe.pointer, size u64) {
	ptr_array := unsafe.cast_to_slice(obj, size/8)
	for i := i32(0); i < i32(len(ptr_array)); i += 1 {
		child_ptr := ptr_array[i]
		if child_ptr != 0 {
			gc_mark_object(child_ptr)
		}
	}
}

func gc_mark_termination_phase() {
	global_heap.gc_phase = gc_mark_termination

	for len(global_heap.gray_queue) > 0 {
		obj_addr := global_heap.gray_queue[0]
		global_heap.gray_queue = global_heap.gray_queue[1:]
		gc_process_object(obj_addr)
	}
}

func gc_sweep_phase() {
	global_heap.gc_phase = gc_sweep

	live_count := 0
	new_objects := make(gc_object[], 0)

	for i := i32(0); i < i32(len(global_heap.objects)); i += 1 {
		obj := global_heap.objects[i]

		if obj.color == gc_black {
			obj.color = gc_white
			new_objects = append(new_objects, obj)
			live_count += 1
		} else {
			global_heap.total_freed += obj.size
			free_memory(obj.addr, obj.size)
		}
	}

	global_heap.objects = new_objects
	gc_stats_data.live_objects = i32(live_count)
	gc_stats_data.heap_size = global_heap.total_alloc - global_heap.total_freed
}

func gc_add_root(addr u64) {
	gc_roots = append(gc_roots, addr)
}

func gc_write_barrier(src u64, dst u64) {
	if !gc_enabled || global_heap.gc_phase != gc_mark {
		return
	}

	global_heap.barrier_buf = append(global_heap.barrier_buf, dst)

	if len(global_heap.barrier_buf) > 1024 {
		for _, obj_addr := range global_heap.barrier_buf {
			gc_mark_object(obj_addr)
		}
		global_heap.barrier_buf = make(u64[], 0)
	}
}

func gc_get_stats() gc_stats* {
	return &gc_stats_data
}

func gc_enable() {
	gc_enabled = true
}

func gc_disable() {
	gc_enabled = false
}

func gc_is_pointer(addr u64) bool {
	return addr > 1024*1024*1024
}

func allocate_memory(size u64) u64 {
	return 0
}

func free_memory(addr u64, size u64) {
}

func get_ticks() u64 {
	return 0
}

func get_time_ns() i64 {
	return 0
}
