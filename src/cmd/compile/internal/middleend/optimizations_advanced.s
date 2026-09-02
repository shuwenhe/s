package optimizations_advanced

const INLINE_COST_CALL = 1
const INLINE_COST_LOAD = 1
const INLINE_COST_STORE = 2
const INLINE_COST_BINOP = 1
const INLINE_COST_BRANCH = 5
const INLINE_COST_LOOP = 10

const INLINE_THRESHOLD_SMALL = 40
const INLINE_THRESHOLD_MEDIUM = 80
const INLINE_THRESHOLD_LARGE = 160

struct inline_candidate {
    func_name string
    cost int
    benefit int
    call_count int
    is_recursive int
}

struct escape_node {
    var_name string
    escapes int
    depth int
}

struct escape_graph {
    nodes escape_node[]
}

func estimate_inline_cost(ir_function func) int {
    cost := 0
    
    for b_idx := 0; b_idx < func.blocks.len(); b_idx = b_idx + 1 {
        block := func.blocks[b_idx]
        
        for i := 0; i < block.instructions.len(); i = i + 1 {
            instr := block.instructions[i]
            
            if instr.instr_type == IR_INSTR_CALL {
                cost = cost + INLINE_COST_CALL
            } else if instr.instr_type == IR_INSTR_LOAD {
                cost = cost + INLINE_COST_LOAD
            } else if instr.instr_type == IR_INSTR_STORE {
                cost = cost + INLINE_COST_STORE
            } else if instr.instr_type == IR_INSTR_BINOP {
                cost = cost + INLINE_COST_BINOP
            } else if instr.instr_type == IR_INSTR_BRANCH {
                cost = cost + INLINE_COST_BRANCH
            }
        }
    }
    
    cost
}

func is_inline_candidate(ir_function func) int {
    cost := estimate_inline_cost(func)
    
    if cost > INLINE_THRESHOLD_SMALL {
        return 0
    }
    
    if func.is_recursive != 0 {
        return 0
    }
    
    return 1
}

func inline_function_call(ir_module module, ir_instruction call_instr, ir_function callee) ir_instruction[] {
    result := ir_instruction[]()
    
    for i := 0; i < callee.blocks.len(); i = i + 1 {
        block := callee.blocks[i]
        
        for j := 0; j < block.instructions.len(); j = j + 1 {
            instr := block.instructions[j]
            
            if instr.instr_type == IR_INSTR_RETURN {
                result = append(result, ir_instr_assign(call_instr.result, instr.operands[0]))
            } else {
                result = append(result, instr)
            }
        }
    }
    
    result
}

func perform_inlining(ir_module module) {
    for f_idx := 0; f_idx < module.functions.len(); f_idx = f_idx + 1 {
        func := module.functions[f_idx]
        
        for b_idx := 0; b_idx < func.blocks.len(); b_idx = b_idx + 1 {
            block := func.blocks[b_idx]
            
            new_instrs := ir_instruction[]()
            
            for i := 0; i < block.instructions.len(); i = i + 1 {
                instr := block.instructions[i]
                
                if instr.instr_type == IR_INSTR_CALL {
                    callee_name := instr.operands[0].const_value
                    
                    callee := find_function(&module, callee_name)
                    if callee != 0 && is_inline_candidate(callee) != 0 {
                        inlined := inline_function_call(&module, instr, callee)
                        for j := 0; j < inlined.len(); j = j + 1 {
                            new_instrs = append(new_instrs, inlined[j])
                        }
                    } else {
                        new_instrs = append(new_instrs, instr)
                    }
                } else {
                    new_instrs = append(new_instrs, instr)
                }
            }
            
            block.instructions = new_instrs
        }
    }
}

func escape_analyze_var(ir_function func, string var_name) int {
    escapes := 0
    
    for b_idx := 0; b_idx < func.blocks.len(); b_idx = b_idx + 1 {
        block := func.blocks[b_idx]
        
        for i := 0; i < block.instructions.len(); i = i + 1 {
            instr := block.instructions[i]
            
            if instr.instr_type == IR_INSTR_STORE {
                if instr.operands[0].var_name == var_name {
                    escapes = 1
                }
            } else if instr.instr_type == IR_INSTR_CALL {
                for j := 0; j < instr.operands.len(); j = j + 1 {
                    if instr.operands[j].var_name == var_name {
                        escapes = 1
                    }
                }
            }
        }
    }
    
    escapes
}

func build_escape_graph(ir_function func) escape_graph {
    graph := escape_graph { nodes: escape_node[]() }
    
    for b_idx := 0; b_idx < func.blocks.len(); b_idx = b_idx + 1 {
        block := func.blocks[b_idx]
        
        for i := 0; i < block.instructions.len(); i = i + 1 {
            instr := block.instructions[i]
            
            if instr.instr_type == IR_INSTR_ALLOC {
                var_name := instr.result.var_name
                escapes := escape_analyze_var(func, var_name)
                
                node := escape_node { var_name: var_name, escapes: escapes, depth: 0 }
                graph.nodes = append(graph.nodes, node)
            }
        }
    }
    
    graph
}

func perform_escape_analysis(ir_module module) {
    for f_idx := 0; f_idx < module.functions.len(); f_idx = f_idx + 1 {
        func := module.functions[f_idx]
        
        graph := build_escape_graph(func)
        
        for i := 0; i < graph.nodes.len(); i = i + 1 {
            node := graph.nodes[i]
            
            if node.escapes == 0 {
            }
        }
    }
}

func find_function(ir_module module, string name) ir_function {
    for i := 0; i < module.functions.len(); i = i + 1 {
        if module.functions[i].name == name {
            return module.functions[i]
        }
    }
    
    ir_function { name: "invalid" }
}

func devirtualize_interface_call(ir_instruction call_instr, string type_name) ir_instruction {
    call_instr
}

func perform_devirtualization(ir_module module) {
    for f_idx := 0; f_idx < module.functions.len(); f_idx = f_idx + 1 {
        func := module.functions[f_idx]
        
        for b_idx := 0; b_idx < func.blocks.len(); b_idx = b_idx + 1 {
            block := func.blocks[b_idx]
            
            for i := 0; i < block.instructions.len(); i = i + 1 {
                instr := block.instructions[i]
                
                if instr.instr_type == IR_INSTR_CALL {
                }
            }
        }
    }
}

func ir_instr_assign(ir_value result, ir_value value) ir_instruction {
    instr := ir_instruction { instr_type: IR_INSTR_ASSIGN, result: result }
    instr.operands = append(instr.operands, value)
    instr
}
