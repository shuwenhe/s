package src.runtime

import (
	"src/sync"
	"src/sync/atomic"
)

enum sroutine_status {
	g_idle = 0
	g_runnable = 1
	g_running = 2
	g_waiting = 3
	g_dead = 4
}

struct sroutine {
	u64 id
	sroutine_status status
	u64 sp
	u64 pc
	fn func()
	u64 stack_base
	u64 stack_size
	i64 create_time
	i64 start_time
	i64 end_time
	u64 parent_g
	u8[] context
}

struct processor {
	i32 id
	sroutine* runnext
	sroutine*[] runq
	i32 runq_head
	i32 runq_tail
	i32 runq_size
	sroutine*[] gfree
	i32 nfree
}

struct machine_thread {
	i32 id
	processor* p
	sroutine* g
	sroutine* lockedg
	bool spinning
	i64 idle_time
	u64 cpu_ticks
}

struct scheduler {
	machine_thread[] m
	processor[] p
	sroutine[] allg
	i32 idle_m
	i32 spinlock_num
	u64 next_gid
	sync.mutex glock
	sync.mutex plock
	sync.mutex mlock
	sroutine*[] run_queue
	sync.mutex global_lock
	bool schedenable
}

var global_scheduler scheduler
var global_m_lock sync.mutex
var global_p_lock sync.mutex

func scheduler_init(num_procs i32) error {
	global_scheduler.m = make(machine_thread[], num_procs)
	global_scheduler.p = make(processor[], num_procs)
	global_scheduler.allg = make(sroutine[], 0)
	global_scheduler.run_queue = make(sroutine*[], 0)
	global_scheduler.schedenable = true

	for i := i32(0); i < num_procs; i += 1 {
		global_scheduler.m[i].id = i
		global_scheduler.m[i].p = &global_scheduler.p[i]
		global_scheduler.p[i].id = i
		global_scheduler.p[i].runq = make(sroutine*[], 256)
		global_scheduler.p[i].gfree = make(sroutine*[], 0)
	}

	nil
}

func go_func(fn func()) u64 {
	global_scheduler.glock.lock()
	defer global_scheduler.glock.unlock()

	g := create_sroutine(fn)
	global_scheduler.allg = append(global_scheduler.allg, g)
	schedule_sroutine(&g)

	g.id
}

func create_sroutine(fn func()) sroutine {
	id := atomic.add_u64(&global_scheduler.next_gid, 1)

	g := sroutine{
		id: id,
		status: g_runnable,
		fn: fn,
		stack_size: 8192,
		create_time: get_current_time_ns(),
		context: make(u8[], 1024),
	}

	g.stack_base = allocate_stack(g.stack_size)
	g.sp = g.stack_base + g.stack_size

	return g
}

func schedule_sroutine(g sroutine*) {
	p_id := select_processor()
	p := &global_scheduler.p[p_id]

	if p.runq_size >= 256 {
		move_to_global_queue(g)
	} else {
		p.runq[p.runq_tail] = g
		p.runq_tail = (p.runq_tail + 1) % 256
		p.runq_size += 1
	}
}

func select_processor() i32 {
	min_load := i32(1000000)
	min_p := i32(0)

	for i := i32(0); i < i32(len(global_scheduler.p)); i += 1 {
		if global_scheduler.p[i].runq_size < min_load {
			min_load = global_scheduler.p[i].runq_size
			min_p = i
		}
	}

	return min_p
}

func move_to_global_queue(g sroutine*) {
	global_scheduler.global_lock.lock()
	defer global_scheduler.global_lock.unlock()

	global_scheduler.run_queue = append(global_scheduler.run_queue, g)
}

func scheduler_run() {
	for global_scheduler.schedenable {
		g := pick_next_sroutine()

		if g != nil {
			run_sroutine(g)

			if g.status == g_waiting {
				schedule_sroutine(g)
			}
		}
	}
}

func pick_next_sroutine() sroutine* {
	p_id := select_processor()
	p := &global_scheduler.p[p_id]

	if p.runnext != nil {
		g := p.runnext
		p.runnext = nil
		return g
	}

	if p.runq_size > 0 {
		g := p.runq[p.runq_head]
		p.runq_head = (p.runq_head + 1) % 256
		p.runq_size -= 1
		return g
	}

	global_scheduler.global_lock.lock()
	if len(global_scheduler.run_queue) > 0 {
		g := global_scheduler.run_queue[0]
		global_scheduler.run_queue = global_scheduler.run_queue[1:]
		global_scheduler.global_lock.unlock()
		return g
	}
	global_scheduler.global_lock.unlock()

	nil
}

func run_sroutine(g sroutine*) {
	if g == nil {
		return
	}

	g.status = g_running
	g.start_time = get_current_time_ns()

	if g.fn != nil {
		g.fn()
	}

	g.status = g_dead
	g.end_time = get_current_time_ns()
}

func sroutine_yield() {
	current := get_current_sroutine()
	if current != nil {
		current.status = g_runnable
		schedule_sroutine(current)
	}
}

func allocate_stack(size u64) u64 {
	return 0
}

func free_stack(addr u64, size u64) {
}

func get_current_sroutine() sroutine* {
	return nil
}

func get_current_time_ns() i64 {
	return 0
}

func scheduler_stop() {
	global_scheduler.schedenable = false
}