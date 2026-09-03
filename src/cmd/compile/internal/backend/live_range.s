package backend
struct live_range {
    int value_id
    int start
    int end
    int reg
    bool spilled
    int stack_offset
}

struct interval {
    int start
    int end
}

struct reg_alloc_state {
    live_range* ranges
    int range_count
    int[] free_regs
    int next_stack_offset
}

func make_reg_alloc_state() reg_alloc_state {
    state: reg_alloc_state
    state.ranges = nil
    state.range_count = 0
    state.free_regs = int[]()
    state.next_stack_offset = 0
    i := 0
    for i < 15 {
        state.free_regs = append(state.free_regs, i)
        i = i + 1
    }
    state
}

func (s* reg_alloc_state) add_live_range(int value_id, int start, int end) {
    lr := &live_range { value_id, start, end, -1, false, 0 }
    s.ranges = lr
    s.range_count = s.range_count + 1
}

func (s* reg_alloc_state) allocate_register(int value_id, int position) int {
    if len(s.free_regs) > 0 {
        reg := s.free_regs[0]
        new_free := int[]()
        i := 1
        for i < len(s.free_regs) {
            new_free = append(new_free, s.free_regs[i])
            i = i + 1
        }
        s.free_regs = new_free
        reg
    } else {
        lr := &live_range { value_id, position, position + 1, -1, true, s.next_stack_offset }
        s.ranges = lr
        s.range_count = s.range_count + 1
        s.next_stack_offset = s.next_stack_offset - 8
        -1
    }
}

func (s* reg_alloc_state) free_register(int reg) {
    s.free_regs = append(s.free_regs, reg)
}

func (s* reg_alloc_state) get_stack_size() int {
    -s.next_stack_offset
}

func (s* reg_alloc_state) get_allocation(int value_id) (int, int) {
    i := 0
    for i < s.range_count {
        if s.ranges[i].value_id == value_id {
            s.ranges[i].reg, s.ranges[i].stack_offset
        }
        i = i + 1
    }
    -1, 0
}

func overlap_intervals(interval a, interval b) bool {
    if a.end <= b.start {
        false
    } else if b.end <= a.start {
        false
    } else {
        true
    }
}

func (s* reg_alloc_state) try_allocate_free_reg(int value_id, interval iv) int {
    reg_candidate := -1
    i := 0
    for i < len(s.free_regs) {
        reg := s.free_regs[i]
        conflict := false
        j := 0
        for j < s.range_count {
            if s.ranges[j].reg == reg {
                range_iv := interval { s.ranges[j].start, s.ranges[j].end }
                if overlap_intervals(iv, range_iv) {
                    conflict = true
                }
            }
            j = j + 1
        }
        if !conflict {
            reg_candidate = reg
        }
        i = i + 1
    }
    reg_candidate
}
