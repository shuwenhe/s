package register_allocator

struct live_range {
    int value_id
    int start_block
    int start_instr
    int end_block
    int end_instr
    int reg
    int spilled
    int priority
}

struct interference_graph {
    int node_count
    []int[] adjacency
    []int color
    []int degree
    []int spill_cost
}

struct register_allocator {
    int num_regs
    []int available_regs
    int reg_count
    live_range[] ranges
    int range_count
    interference_graph graph
    []int spill_list
    int spill_count
}

func register_allocator_new(int num_regs) register_allocator* {
    allocator := register_allocator {
        num_regs: num_regs,
        available_regs: new int[16],
        reg_count: 0,
        ranges: new live_range[512],
        range_count: 0,
        spill_list: new int[128],
        spill_count: 0,
    }

    i := 0
    for i < num_regs {
        allocator.available_regs[i] = i
        i = i + 1
    }
    allocator.reg_count = num_regs

    &allocator
}

func (allocator* register_allocator) compute_live_ranges(value[] all_values, int num_values) int {
    i := 0
    for i < num_values {
        v := all_values[i]
        
        live_range := live_range {
            value_id: v.id,
            start_block: v.block,
            start_instr: 0,
            end_block: v.block,
            end_instr: 0,
            reg: -1,
            spilled: 0,
            priority: 0,
        }

        allocator.ranges[allocator.range_count] = &live_range
        allocator.range_count = allocator.range_count + 1
        
        i = i + 1
    }
    
    allocator.range_count
}

func (allocator* register_allocator) build_interference_graph() int {
    graph := interference_graph {
        node_count: allocator.range_count,
        adjacency: new []int[allocator.range_count],
        color: new int[allocator.range_count],
        degree: new int[allocator.range_count],
        spill_cost: new int[allocator.range_count],
    }
    
    i := 0
    for i < graph.node_count {
        graph.adjacency[i] = new int[graph.node_count]
        graph.color[i] = -1
        graph.degree[i] = 0
        graph.spill_cost[i] = 0
        
        j := 0
        for j < graph.node_count {
            graph.adjacency[i][j] = 0
            j = j + 1
        }
        
        i = i + 1
    }
    
    i = 0
    for i < allocator.range_count {
        range_i := allocator.ranges[i]
        
        j := 0
        for j < allocator.range_count {
            if i != j {
                range_j := allocator.ranges[j]
                
                if ranges_interfere(range_i, range_j) == 1 {
                    graph.adjacency[i][j] = 1
                    graph.adjacency[j][i] = 1
                    graph.degree[i] = graph.degree[i] + 1
                    graph.degree[j] = graph.degree[j] + 1
                }
            }
            
            j = j + 1
        }
        
        i = i + 1
    }
    
    allocator.graph = graph
    0
}

func ranges_interfere(live_range* range_a, live_range* range_b) int {
    if range_a.start_block == range_b.start_block {
        if range_a.start_instr < range_b.end_instr && range_b.start_instr < range_a.end_instr {
            return 1
        }
    }
    
    return 0
}

func (allocator* register_allocator) color_graph() int {
    graph := allocator.graph
    
    worklist := new int[graph.node_count]
    worklist_size := 0
    
    i := 0
    for i < graph.node_count {
        if graph.degree[i] >= allocator.num_regs {
            worklist[worklist_size] = i
            worklist_size = worklist_size + 1
        }
        i = i + 1
    }
    
    simplified := new int[graph.node_count]
    simplified_count := 0
    
    for worklist_size > 0 {
        worklist_size = worklist_size - 1
        node := worklist[worklist_size]
        
        simplified[simplified_count] = node
        simplified_count = simplified_count + 1
        
        j := 0
        for j < graph.node_count {
            if graph.adjacency[node][j] == 1 {
                graph.degree[j] = graph.degree[j] - 1
                
                if graph.degree[j] >= allocator.num_regs {
                    worklist[worklist_size] = j
                    worklist_size = worklist_size + 1
                }
            }
            j = j + 1
        }
    }
    
    i = simplified_count - 1
    for i >= 0 {
        node := simplified[i]
        
        used_colors := new int[allocator.num_regs]
        
        j := 0
        for j < graph.node_count {
            if graph.adjacency[node][j] == 1 && graph.color[j] != -1 {
                used_colors[graph.color[j]] = 1
            }
            j = j + 1
        }
        
        color := 0
        for color < allocator.num_regs {
            if used_colors[color] == 0 {
                graph.color[node] = color
                break
            }
            color = color + 1
        }
        
        if graph.color[node] == -1 {
            allocator.spill_list[allocator.spill_count] = node
            allocator.spill_count = allocator.spill_count + 1
            allocator.ranges[node].spilled = 1
        }
        
        i = i - 1
    }
    
    allocator.spill_count
}

func (allocator* register_allocator) assign_registers() int {
    i := 0
    for i < allocator.range_count {
        range_obj := allocator.ranges[i]
        
        if range_obj.spilled == 0 {
            color := allocator.graph.color[i]
            if color >= 0 && color < allocator.num_regs {
                range_obj.reg = allocator.available_regs[color]
            }
        }
        
        i = i + 1
    }
    
    allocator.spill_count
}

func (allocator* register_allocator) perform_move_coalescing() int {
    i := 0
    for i < allocator.range_count {
        range_i := allocator.ranges[i]
        
        j := i + 1
        for j < allocator.range_count {
            range_j := allocator.ranges[j]
            
            if can_coalesce(range_i, range_j) == 1 {
                range_j.reg = range_i.reg
            }
            
            j = j + 1
        }
        
        i = i + 1
    }
    
    0
}

func can_coalesce(live_range* range_a, live_range* range_b) int {
    if range_a.start_block != range_b.start_block {
        return 0
    }
    
    if ranges_interfere(range_a, range_b) == 1 {
        return 0
    }
    
    return 1
}

func (allocator* register_allocator) generate_spill_code(int num_stack_slots) int {
    i := 0
    for i < allocator.spill_count {
        spill_node := allocator.spill_list[i]
        
        stack_slot := i
        allocator.ranges[spill_node].reg = -stack_slot - 1
        
        i = i + 1
    }
    
    allocator.spill_count
}

func (allocator* register_allocator) optimize_allocation_order() int {
    i := 0
    for i < allocator.range_count {
        allocator.ranges[i].priority = compute_priority(allocator.ranges[i])
        i = i + 1
    }
    
    sort_by_priority(allocator.ranges, allocator.range_count)
    
    0
}

func compute_priority(live_range* range_obj) int {
    priority := 0
    
    length := range_obj.end_instr - range_obj.start_instr
    if length > 100 {
        priority = priority + 1
    }
    
    priority
}

func sort_by_priority(live_range[] ranges, int count) int {
    i := 0
    for i < count {
        j := i + 1
        for j < count {
            if ranges[i].priority < ranges[j].priority {
                temp := ranges[i]
                ranges[i] = ranges[j]
                ranges[j] = temp
            }
            j = j + 1
        }
        i = i + 1
    }
    
    0
}

func (allocator* register_allocator) verify_coloring() int {
    i := 0
    for i < allocator.range_count {
        range_i := allocator.ranges[i]
        
        if range_i.spilled == 0 {
            j := 0
            for j < allocator.range_count {
                if i != j {
                    range_j := allocator.ranges[j]
                    
                    if range_j.spilled == 0 {
                        if allocator.graph.adjacency[i][j] == 1 {
                            if range_i.reg == range_j.reg {
                                return 0
                            }
                        }
                    }
                }
                
                j = j + 1
            }
        }
        
        i = i + 1
    }
    
    1
}

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
