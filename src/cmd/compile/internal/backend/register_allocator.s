package backend

const reg_rax = 0
const reg_rbx = 1
const reg_rcx = 2
const reg_rdx = 3
const reg_rsi = 4
const reg_rdi = 5
const reg_r8 = 6
const reg_r9 = 7
const reg_r10 = 8
const reg_r11 = 9
const reg_r12 = 10
const reg_r13 = 11
const reg_r14 = 12
const reg_r15 = 13

struct live_interval {
    int var_id
    int start
    int end
    int spilled
    int assigned_reg
}

struct interference_graph {
    int[] nodes
    int[][] edges
}

struct register_allocator {
    live_interval[] intervals
    interference_graph graph
    int spill_count
    int reserved_regs
}

func register_allocator_new() register_allocator {
    allocator := register_allocator {
        intervals: live_interval[] {},
        graph: interference_graph { nodes: int[] {}, edges: int[][] {} },
        spill_count: 0,
        reserved_regs: 0
    }
    allocator
}

func register_allocator_build_intervals(allocator* register_allocator, x86_instruction[] instrs) {
    for i := 0; i < instrs.len(); i = i + 1 {
        instr := instrs[i]
        
        interval := live_interval {
            var_id: i,
            start: i,
            end: i,
            spilled: 0,
            assigned_reg: -1
        }
        
        allocator.intervals = append(allocator.intervals, interval)
    }
}

func register_allocator_build_interference_graph(allocator* register_allocator) {
    graph_size := allocator.intervals.len()
    
    for i := 0; i < graph_size; i = i + 1 {
        row := int[] {}
        for j := 0; j < graph_size; j = j + 1 {
            row = append(row, 0)
        }
        allocator.graph.edges = append(allocator.graph.edges, row)
    }
    
    for i := 0; i < allocator.intervals.len(); i = i + 1 {
        for j := i + 1; j < allocator.intervals.len(); j = j + 1 {
            interval_i := allocator.intervals[i]
            interval_j := allocator.intervals[j]
            
            if intervals_interfere(interval_i, interval_j) != 0 {
                allocator.graph.edges[i][j] = 1
                allocator.graph.edges[j][i] = 1
            }
        }
    }
}

func intervals_interfere(i1 live_interval, i2 live_interval) int {
    if i1.start > i2.end || i2.start > i1.end {
        0
    } else {
        1
    }
}

func register_allocator_allocate(allocator* register_allocator) {
    for i := 0; i < allocator.intervals.len(); i = i + 1 {
        interval := allocator.intervals[i]
        assigned := -1
        for reg := 0; reg < 14; reg = reg + 1 {
            blocked := 0
            for j := 0; j < i; j = j + 1 {
                if allocator.intervals[j].assigned_reg == reg &&
                    allocator.graph.edges[i][j] != 0 {
                    blocked = 1
                    break
                }
            }
            if blocked == 0 {
                assigned = reg
                break
            }
        }

        if assigned >= 0 {
            interval.assigned_reg = assigned
        } else {
            interval.spilled = 1
            allocator.spill_count = allocator.spill_count + 1
        }
        
        allocator.intervals[i] = interval
    }
}

func get_available_registers(allocator* register_allocator) int[] {
    available := int[] {}
    
    for reg := 0; reg < 14; reg = reg + 1 {
        is_available := 1
        
        for i := 0; i < allocator.intervals.len(); i = i + 1 {
            if allocator.intervals[i].assigned_reg == reg {
                is_available = 0
            }
        }
        
        if is_available != 0 {
            available = append(available, reg)
        }
    }
    
    available
}

func register_allocator_insert_spill_code(allocator* register_allocator, x86_instruction[] instrs*) {
    for i := 0; i < allocator.intervals.len(); i = i + 1 {
        interval := allocator.intervals[i]
        
        if interval.spilled != 0 {
            stack_offset := i * 8
            
            spill_instr := x86_instruction {
                instr_type: instr_store,
                operand1: x86_operand { operand_type: operand_reg, reg_id: reg_rax },
                operand2: x86_operand { operand_type: operand_mem, mem_base: "rbp", mem_offset: -stack_offset },
                operand3: x86_operand { operand_type: 0 }
            }
            
            instrs.append(spill_instr)
        }
    }
}

struct spill_reload_action {
    int value_id
    int stack_offset
    int instruction_index
    bool reload
}

// Generate both sides of each spill. The backend can lower these actions to
// target-specific loads and stores after register allocation.
func register_allocator_spill_reload_plan(register_allocator* allocator) spill_reload_action[] {
    actions := spill_reload_action[]()
    for i := 0; i < allocator.intervals.len(); i = i + 1 {
        interval := allocator.intervals[i]
        if interval.spilled != 0 {
            offset := -(i + 1) * 8
            actions.push(spill_reload_action { value_id: interval.var_id, stack_offset: offset, instruction_index: interval.start, reload: false })
            actions.push(spill_reload_action { value_id: interval.var_id, stack_offset: offset, instruction_index: interval.end, reload: true })
        }
    }
    actions
}
