package src.runtime

import (
	"src/sync"
	"src/unsafe"
	"src/fmt"
	"src/syscall"
)

enum panic_state {
	panic_normal = 0
	panic_running = 1
	panic_recovering = 2
}

struct defer_entry {
	u64 pc
	u64 sp
	func() fn
	unsafe.pointer arg
	defer_entry* next
}

struct panic_entry {
	string message
	string[] stack_trace
	bool recovered
	i64 panic_time
	panic_state state
	defer_entry* defer_stack
}

struct exception_context {
	panic_entry* current_panic
	panic_entry[] panic_stack
	defer_entry* defer_stack
	u64 recovery_pc
	u64 recovery_sp
	sync.mutex lock
}

exception_context global_exception_context

func init_exception_context() error {
	global_exception_context.panic_stack = make(panic_entry[], 0)
	global_exception_context.defer_stack = nil
	nil
}

func defer_call(fn func(), arg unsafe.pointer) {
	entry := &defer_entry{
		pc: 0,
		sp: 0,
		fn: fn,
		arg: arg,
		next: global_exception_context.defer_stack,
	}

	global_exception_context.defer_stack = entry
}

func panic_impl(msg string) {
	global_exception_context.lock.lock()
	defer global_exception_context.lock.unlock()

	stack_trace := capture_stack_trace()

	panic_entry := panic_entry{
		message: msg,
		stack_trace: stack_trace,
		recovered: false,
		panic_time: get_current_time_ns(),
		state: panic_normal,
		defer_stack: global_exception_context.defer_stack,
	}

	global_exception_context.panic_stack = append(global_exception_context.panic_stack, panic_entry)
	global_exception_context.current_panic = &panic_entry

	panic_entry.state = panic_running

	run_defer_stack(&panic_entry)

	if !panic_entry.recovered {
		abort_with_panic_message(msg, stack_trace)
	}
}

func run_defer_stack(p panic_entry*) {
	defer_entry := p.defer_stack

	for defer_entry != nil {
		if defer_entry.fn != nil {
			defer_entry.fn()
		}
		defer_entry = defer_entry.next
	}
}

func recover() unsafe.pointer {
	global_exception_context.lock.lock()
	defer global_exception_context.lock.unlock()

	if len(global_exception_context.panic_stack) == 0 {
		return nil
	}

	current := &global_exception_context.panic_stack[len(global_exception_context.panic_stack)-1]

	if current.state != panic_running {
		return nil
	}

	current.recovered = true
	current.state = panic_recovering

	if len(global_exception_context.panic_stack) > 0 {
		global_exception_context.panic_stack = global_exception_context.panic_stack[:len(global_exception_context.panic_stack)-1]
	}

	global_exception_context.defer_stack = nil

	unsafe.pointer(0)
}

func get_panic_message() string {
	if global_exception_context.current_panic != nil {
		return global_exception_context.current_panic.message
	}
	return ""
}

func get_stack_trace() string[] {
	if global_exception_context.current_panic != nil {
		return global_exception_context.current_panic.stack_trace
	}
	return make(string[], 0)
}

func capture_stack_trace() string[] {
	trace := make(string[], 0)
	return trace
}

func abort_with_panic_message(msg string, trace string[]) {
	fmt.fprintf(fmt.stderr, "panic: %s\n", msg)

	for i := i32(0); i < i32(len(trace)); i += 1 {
		fmt.fprintf(fmt.stderr, "%s\n", trace[i])
	}

	syscall.exit(2)
}

struct defer_context {
	defer_entry* stack
	i32 count
}

func (defer_context* dc) push(fn func(), arg unsafe.pointer) {
	entry := &defer_entry{
		fn: fn,
		arg: arg,
		next: dc.stack,
	}
	dc.stack = entry
	dc.count += 1
}

func (defer_context* dc) pop() defer_entry* {
	if dc.stack == nil {
		return nil
	}

	entry := dc.stack
	dc.stack = entry.next
	dc.count -= 1
	return entry
}

func (dc defer_context*) run_all() {
	for dc.stack != nil {
		entry := dc.pop()
		if entry != nil && entry.fn != nil {
			entry.fn()
		}
	}
}

func (dc defer_context*) clear() {
	dc.stack = nil
	dc.count = 0
}

struct try_catch_block {
	try_fn func()
	catch_fn func(string)
	finally_fn func()
	defer_stack defer_entry*
}

func try_catch(try_fn func(), catch_fn func(string), finally_fn func()) {
	block := try_catch_block{
		try_fn: try_fn,
		catch_fn: catch_fn,
		finally_fn: finally_fn,
		defer_stack: global_exception_context.defer_stack,
	}

	defer_saved := global_exception_context.defer_stack
	global_exception_context.defer_stack = nil

	current_panic_count := i32(len(global_exception_context.panic_stack))

	if try_fn != nil {
		try_fn()
	}

	new_panic_count := i32(len(global_exception_context.panic_stack))
	if new_panic_count > current_panic_count {
		if catch_fn != nil {
			panic_msg := get_panic_message()
			catch_fn(panic_msg)
		}
		recover()
	}

	if finally_fn != nil {
		finally_fn()
	}

	global_exception_context.defer_stack = defer_saved
}
