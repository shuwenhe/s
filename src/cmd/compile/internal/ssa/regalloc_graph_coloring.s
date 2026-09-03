package internal.ssa

struct live_range {
    int var_id
    int start_pos
    int end_pos
    int start_block
    int end_block
    int reg_assigned
    int on_stack
    int stack_pos
}

struct interference_edge {
    int var1_id
    int var2_id
    int weight
}

struct interference_graph {
    int*[] adjacency
    int* node_colors
    int* spill_costs
    int node_count
    int color_count
}

struct regalloc_state {
    live_range*[] ranges
    int range_count
    
    interference_edge*[] edges
    int edge_count
    
    interference_graph* graph
    
    int*[] available_regs
    int available_count
}

func analyze_liveness(ssa_block* block, live_range*[] ranges) int {
    if block == 0 || block.values == 0 {
        return 0
    }
    
    int i = 0
    int var_id = 0
    int last_use = 0
    
    for i = 0; i < 1000; i = i + 1 {
        if block.values[i] == 0 {
            break
        }
        
        live_range* range = new live_range
        range.var_id = var_id
        range.start_pos = i
        range.end_pos = i
        range.start_block = block.id
        range.end_block = block.id
        range.reg_assigned = -1
        range.on_stack = 0
        range.stack_pos = 0
        
        ranges[var_id] = range
        var_id = var_id + 1
        last_use = i
    }
    
    return var_id
}

func compute_live_ranges(ssa_function* func, live_range*[] ranges) int {
    if func == 0 || func.blocks == 0 {
        return 0
    }
    
    int total_ranges = 0
    int i = 0
    
    for i = 0; i < func.block_count; i = i + 1 {
        int ranges_in_block = analyze_liveness(func.blocks[i], ranges)
        total_ranges = total_ranges + ranges_in_block
    }
    
    return total_ranges
}

func build_interference_graph(live_range*[] ranges, int range_count) interference_graph* {
    if ranges == 0 {
        return 0
    }
    
    interference_graph* graph = new interference_graph
    graph.adjacency = int*[range_count]
    graph.node_colors = int[range_count]
    graph.spill_costs = int[range_count]
    graph.node_count = range_count
    graph.color_count = 16
    
    int i = 0
    int j = 0
    
    for i = 0; i < range_count; i = i + 1 {
        graph.adjacency[i] = int[range_count]
        graph.node_colors[i] = -1
        graph.spill_costs[i] = 0
        
        for j = 0; j < range_count; j = j + 1 {
            graph.adjacency[i][j] = 0
        }
    }
    
    for i = 0; i < range_count; i = i + 1 {
        for j = i + 1; j < range_count; j = j + 1 {
            live_range* r1 = ranges[i]
            live_range* r2 = ranges[j]
            
            if r1.start_block == r2.start_block || r1.end_block == r2.end_block {
                if r1.start_pos <= r2.end_pos && r2.start_pos <= r1.end_pos {
                    graph.adjacency[i][j] = 1
                    graph.adjacency[j][i] = 1
                    
                    graph.spill_costs[i] = graph.spill_costs[i] + 1
                    graph.spill_costs[j] = graph.spill_costs[j] + 1
                }
            }
        }
    }
    
    return graph
}

func color_interference_graph(interference_graph* graph) int {
    if graph == 0 {
        return -1
    }
    
    int i = 0
    int j = 0
    int attempt = 0
    
    for i = 0; i < graph.node_count; i = i + 1 {
        int used_colors = 0
        int color_mask = 0
        
        for j = 0; j < graph.node_count; j = j + 1 {
            if graph.adjacency[i][j] == 1 && graph.node_colors[j] >= 0 {
                int neighbor_color = graph.node_colors[j]
                
                if neighbor_color < 32 {
                    color_mask = color_mask | (1 << neighbor_color)
                }
            }
        }
        
        int color = 0
        int found = 0
        
        for color = 0; color < graph.color_count; color = color + 1 {
            if (color_mask & (1 << color)) == 0 {
                graph.node_colors[i] = color
                found = 1
                break
            }
        }
        
        if found == 0 {
            graph.node_colors[i] = -2
        }
    }
    
    int uncolored = 0
    for i = 0; i < graph.node_count; i = i + 1 {
        if graph.node_colors[i] == -2 {
            uncolored = uncolored + 1
        }
    }
    
    return uncolored
}

func select_spill_candidate(interference_graph* graph, live_range*[] ranges) int {
    if graph == 0 || ranges == 0 {
        return -1
    }
    
    int best_candidate = -1
    int best_cost = 2147483647
    
    int i = 0
    for i = 0; i < graph.node_count; i = i + 1 {
        if graph.node_colors[i] == -2 {
            int cost = graph.spill_costs[i]
            int live_range_length = ranges[i].end_pos - ranges[i].start_pos
            
            if live_range_length > 0 {
                cost = cost / live_range_length
            }
            
            if cost < best_cost {
                best_cost = cost
                best_candidate = i
            }
        }
    }
    
    return best_candidate
}

func spill_variable(int var_id, interference_graph* graph, int* stack_pos) int {
    if graph == 0 {
        return -1
    }
    
    graph.node_colors[var_id] = -1
    
    int i = 0
    for i = 0; i < graph.node_count; i = i + 1 {
        if graph.adjacency[var_id][i] == 1 && graph.node_colors[i] == -1 {
            graph.adjacency[var_id][i] = 0
            graph.adjacency[i][var_id] = 0
        }
    }
    
    *stack_pos = *stack_pos + 8
    return *stack_pos - 8
}

func allocate_registers(ssa_function* func) int {
    if func == 0 {
        return -1
    }
    
    live_range*[] ranges = live_range*[func.value_count]
    int range_count = compute_live_ranges(func, ranges)
    
    if range_count <= 0 {
        return 0
    }
    
    interference_graph* graph = build_interference_graph(ranges, range_count)
    
    if graph == 0 {
        return -1
    }
    
    int uncolored = color_interference_graph(graph)
    
    int stack_pos = 0
    int spill_attempts = 0
    int max_spill_attempts = 100
    
    for spill_attempts = 0; spill_attempts < max_spill_attempts && uncolored > 0; spill_attempts = spill_attempts + 1 {
        int candidate = select_spill_candidate(graph, ranges)
        
        if candidate < 0 {
            break
        }
        
        int spill_stack = spill_variable(candidate, graph, &stack_pos)
        ranges[candidate].on_stack = 1
        ranges[candidate].stack_pos = spill_stack
        
        uncolored = color_interference_graph(graph)
    }
    
    int i = 0
    for i = 0; i < range_count; i = i + 1 {
        if graph.node_colors[i] >= 0 {
            ranges[i].reg_assigned = graph.node_colors[i]
        } else if ranges[i].on_stack == 0 {
            ranges[i].on_stack = 1
            ranges[i].stack_pos = stack_pos
            stack_pos = stack_pos + 8
        }
    }
    
    return stack_pos
}

func mark_registers_for_function(ssa_function* func, live_range*[] ranges) int {
    if func == 0 || func.blocks == 0 {
        return 0
    }
    
    int i = 0
    int j = 0
    
    for i = 0; i < func.block_count; i = i + 1 {
        ssa_block* block = func.blocks[i]
        
        if block == 0 || block.values == 0 {
            continue
        }
        
        for j = 0; j < 1000; j = j + 1 {
            if block.values[j] == 0 {
                break
            }
            
            if j < func.value_count && ranges[j] != 0 {
                if ranges[j].reg_assigned >= 0 {
                    block.values[j].aux_int[0] = ranges[j].reg_assigned
                }
            }
        }
    }
    
    return 0
}

func regalloc_greedy_graph_coloring(ssa_function* func) int {
    if func == 0 {
        return -1
    }
    
    live_range*[] ranges = live_range*[func.value_count]
    int range_count = compute_live_ranges(func, ranges)
    
    interference_graph* graph = build_interference_graph(ranges, range_count)
    
    int uncolored = color_interference_graph(graph)
    
    mark_registers_for_function(func, ranges)
    
    return uncolored
}
