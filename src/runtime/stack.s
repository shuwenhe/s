package src.runtime

import (
	"src/sync"
)

enum stack_shrink_state {
	shrink_idle = 0
	shrink_in_progress = 1
	shrink_done = 2
}

struct stack_guard {
	u64 limit
	u64 next_call_size
	bool can_split
}

struct stack_frame {
	u64 pc
	u64 sp
	u64 bp
	u64 locals_size
	u64 args_size
}

struct stack_info {
	u64 base
	u64 top
	u64 current_size
	u64 max_size
	u64 min_size
	stack_guard guard
	stack_frame[] frame_stack
	i32 grow_count
	stack_shrink_state shrink_state
	sync.mutex lock
}

const (
	min_stack_size = i32(2048)
	max_stack_size = i32(1024*1024)
	stack_grow_threshold = i32(256)
)

func create_stack(size i32) (stack_info*, error) {
	if size < min_stack_size {
		size = min_stack_size
	}
	if size > max_stack_size {
		return nil, "stack size exceeds maximum"
	}

	base := allocate_stack_memory(i32(size))
	if base == 0 {
		return nil, "failed to allocate stack memory"
	}

	s := &stack_info{
		base: base,
		top: base + u64(size),
		current_size: u64(size),
		max_size: u64(max_stack_size),
		min_size: u64(min_stack_size),
		frame_stack: make(stack_frame[], 0),
		grow_count: 0,
		shrink_state: shrink_idle,
	}

	s.guard.limit = base + u64(stack_grow_threshold)
	s.guard.next_call_size = 0
	s.guard.can_split = true

	return s, nil
}

func (s stack_info*) check_growth(needed u64) error {
	if s == nil {
		return "stack is nil"
	}

	s.lock.lock()
	defer s.lock.unlock()

	current_free := s.top - s.base
	if current_free < needed {
		return grow_stack(s, i32(needed))
	}

	nil
}

func grow_stack(s stack_info*, needed i32) error {
	if s == nil {
		return "stack is nil"
	}

	if s.current_size >= u64(max_stack_size) {
		return "stack overflow: cannot grow further"
	}

	new_size := s.current_size * 2
	if new_size > u64(max_stack_size) {
		new_size = u64(max_stack_size)
	}

	if u64(needed) > new_size-s.current_size {
		return "cannot allocate enough stack space"
	}

	old_base := s.base
	old_size := s.current_size
	new_base := allocate_stack_memory(i32(new_size))

	if new_base == 0 {
		return "failed to allocate new stack"
	}

	copy_stack_memory(new_base, old_base, old_size)

	s.base = new_base
	s.top = new_base + new_size
	s.current_size = new_size
	s.grow_count += 1

	s.guard.limit = new_base + u64(stack_grow_threshold)

	update_stack_pointers(s, old_base, new_base, old_size)

	free_stack_memory(old_base, old_size)

	nil
}

func (s stack_info*) push_frame(pc u64, locals_size u64, args_size u64) stack_frame {
	frame := stack_frame{
		pc: pc,
		sp: 0,
		bp: 0,
		locals_size: locals_size,
		args_size: args_size,
	}

	s.frame_stack = append(s.frame_stack, frame)
	return frame
}

func (s stack_info*) pop_frame() stack_frame* {
	if len(s.frame_stack) == 0 {
		return nil
	}

	frame := s.frame_stack[len(s.frame_stack)-1]
	s.frame_stack = s.frame_stack[:len(s.frame_stack)-1]
	return &frame
}

func (s stack_info*) shrink_check() error {
	if s == nil {
		return "stack is nil"
	}

	s.lock.lock()
	defer s.lock.unlock()

	used := s.base + (s.current_size - (s.top - s.base))
	usage_ratio := f64(used) / f64(s.current_size)

	if usage_ratio < 0.25 && s.current_size > u64(min_stack_size) {
		return shrink_stack(s)
	}

	nil
}

func shrink_stack(s stack_info*) error {
	if s.shrink_state != shrink_idle {
		return "shrink already in progress"
	}

	s.shrink_state = shrink_in_progress

	new_size := s.current_size / 2
	if new_size < u64(min_stack_size) {
		new_size = u64(min_stack_size)
	}

	new_base := allocate_stack_memory(i32(new_size))
	if new_base == 0 {
		s.shrink_state = shrink_idle
		return "failed to allocate smaller stack"
	}

	copy_stack_memory(new_base, s.base, new_size)

	s.base = new_base
	s.top = new_base + new_size
	s.current_size = new_size

	free_stack_memory(s.base, s.current_size)

	s.shrink_state = shrink_done
	nil
}

func (s stack_info*) get_used_size() u64 {
	return s.current_size - (s.top - s.base)
}

func (s stack_info*) get_free_size() u64 {
	return s.top - s.base
}

func (s stack_info*) release() error {
	if s == nil {
		return "stack is nil"
	}

	free_stack_memory(s.base, s.current_size)
	nil
}

func allocate_stack_memory(size i32) u64 {
	return 0
}

func free_stack_memory(base u64, size u64) {
}

func copy_stack_memory(dst u64, src u64, size u64) {
}

func update_stack_pointers(s stack_info*, old_base u64, new_base u64, old_size u64) {
	offset := i64(new_base) - i64(old_base)

	for i := i32(0); i < i32(len(s.frame_stack)); i += 1 {
		if s.frame_stack[i].sp != 0 {
			s.frame_stack[i].sp = u64(i64(s.frame_stack[i].sp) + offset)
		}
		if s.frame_stack[i].bp != 0 {
			s.frame_stack[i].bp = u64(i64(s.frame_stack[i].bp) + offset)
		}
	}
}

struct split_stack_info {
	parent_stack stack_info*
	child_stack stack_info*
	saved_context u8[]
}

func split_stack(parent stack_info*) (split_stack_info*, error) {
	child, err := create_stack(8192)
	if err != nil {
		return nil, err
	}

	split := &split_stack_info{
		parent_stack: parent,
		child_stack: child,
		saved_context: make(u8[], 512),
	}

	return split, nil
}

func (ssi split_stack_info*) restore() error {
	if ssi == nil {
		return "split stack info is nil"
	}

	ssi.child_stack.release()
	nil
}
