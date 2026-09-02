package backend

const REG_RAX = 0
const REG_RBX = 1
const REG_RCX = 2
const REG_RDX = 3
const REG_RSI = 4
const REG_RDI = 5
const REG_R8 = 6
const REG_R9 = 7
const REG_R10 = 8
const REG_R11 = 9
const REG_R12 = 10
const REG_R13 = 11
const REG_R14 = 12
const REG_R15 = 13

struct live_interval {
    var_id int
    start int
    end int
    spilled int
    assigned_reg int
}

struct interference_graph {
    nodes int[]
    edges int[][]
}

struct register_allocator {
    intervals live_interval[]
    graph interference_graph
    spill_count int
    reserved_regs int
}

func register_allocator_new() register_allocator {
    allocator := register_allocator {
        intervals: live_interval[](),
        graph: interference_graph { nodes: int[](), edges: int[][]() },
        spill_count: 0,
        reserved_regs: 0
    }
    allocator
}

func register_allocator_build_intervals(allocator* register_allocator, instrs x86_instruction[]) {
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
        row := int[]()
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
        
        available_regs := get_available_registers(allocator)
        
        if available_regs.len() > 0 {
            interval.assigned_reg = available_regs[0]
        } else {
            interval.spilled = 1
            allocator.spill_count = allocator.spill_count + 1
        }
        
        allocator.intervals[i] = interval
    }
}

func get_available_registers(allocator* register_allocator) int[] {
    available := int[]()
    
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

func register_allocator_insert_spill_code(allocator* register_allocator, instrs* x86_instruction[]) {
    for i := 0; i < allocator.intervals.len(); i = i + 1 {
        interval := allocator.intervals[i]
        
        if interval.spilled != 0 {
            stack_offset := i * 8
            
            spill_instr := x86_instruction {
                instr_type: INSTR_STORE,
                operand1: x86_operand { operand_type: OPERAND_REG, reg_id: REG_RAX },
                operand2: x86_operand { operand_type: OPERAND_MEM, mem_base: "rbp", mem_offset: -stack_offset },
                operand3: x86_operand { operand_type: 0 }
            }
            
            instrs.append(spill_instr)
        }
    }
}
