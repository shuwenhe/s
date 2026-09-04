package ssa

struct rule {
    string id
    string name
    func matcher          
    func transformer      
    int priority          
}

struct rules_engine {
    rule[] rules
    map[string]rule[] rules_by_opcode
    int[] match_count
    int[] transform_count
}

func (engine* rules_engine) init() void {
    engine.rules = vec()
    engine.rules_by_opcode = map()
    
    
    engine.register_const_fold_rules()
    engine.register_algebraic_rules()
    engine.register_expr_rules()
}

func (engine* rules_engine) register_const_fold_rules() void {
    
    engine.add_rule(rule {
        id: "const_add_fold",
        name: "Constant addition folding",
        matcher: func(node IR) bool {
            return node.opcode == "Add" &&
                   node.left.opcode == "Const64" &&
                   node.right.opcode == "Const64"
        },
        transformer: func(node IR) IR {
            let a := node.left.value
            let b := node.right.value
            return IR {
                opcode: "Const64",
                value: a + b,
                pos: node.pos
            }
        },
        priority: 0
    })
    
    
    engine.add_rule(rule {
        id: "const_mul_fold",
        name: "Constant multiplication folding",
        matcher: func(node IR) bool {
            return node.opcode == "Mul" &&
                   node.left.opcode == "Const64" &&
                   node.right.opcode == "Const64"
        },
        transformer: func(node IR) IR {
            let a := node.left.value
            let b := node.right.value
            return IR {
                opcode: "Const64",
                value: a * b,
                pos: node.pos
            }
        },
        priority: 0
    })
    
    
    engine.add_rule(rule {
        id: "const_sub_fold",
        name: "Constant subtraction folding",
        matcher: func(node IR) bool {
            return node.opcode == "Sub" &&
                   node.left.opcode == "Const64" &&
                   node.right.opcode == "Const64"
        },
        transformer: func(node IR) IR {
            let a := node.left.value
            let b := node.right.value
            return IR {
                opcode: "Const64",
                value: a - b,
                pos: node.pos
            }
        },
        priority: 0
    })
    
    
}

func (engine* rules_engine) register_algebraic_rules() void {
    
    engine.add_rule(rule {
        id: "mul_by_zero",
        name: "Multiplication by zero",
        matcher: func(node IR) bool {
            return node.opcode == "Mul" && (
                (node.left.opcode == "Const64" && node.left.value == 0) ||
                (node.right.opcode == "Const64" && node.right.value == 0)
            )
        },
        transformer: func(node IR) IR {
            return IR {
                opcode: "Const64",
                value: 0,
                pos: node.pos
            }
        },
        priority: 1
    })
    
    
    engine.add_rule(rule {
        id: "mul_by_one",
        name: "Multiplication by one",
        matcher: func(node IR) bool {
            if node.opcode != "Mul" {
                return false
            }
            return (node.left.opcode == "Const64" && node.left.value == 1) ||
                   (node.right.opcode == "Const64" && node.right.value == 1)
        },
        transformer: func(node IR) IR {
            if node.left.opcode == "Const64" && node.left.value == 1 {
                return node.right
            }
            return node.left
        },
        priority: 1
    })
    
    
    engine.add_rule(rule {
        id: "add_zero",
        name: "Addition by zero",
        matcher: func(node IR) bool {
            return node.opcode == "Add" && (
                (node.left.opcode == "Const64" && node.left.value == 0) ||
                (node.right.opcode == "Const64" && node.right.value == 0)
            )
        },
        transformer: func(node IR) IR {
            if node.left.opcode == "Const64" && node.left.value == 0 {
                return node.right
            }
            return node.left
        },
        priority: 1
    })
    
    
    engine.add_rule(rule {
        id: "mul_by_two_to_lsh",
        name: "Multiplication by two to left shift",
        matcher: func(node IR) bool {
            if node.opcode != "Mul" {
                return false
            }
            return (node.left.opcode == "Const64" && node.left.value == 2) ||
                   (node.right.opcode == "Const64" && node.right.value == 2)
        },
        transformer: func(node IR) IR {
            let x := if node.left.opcode == "Const64" { node.right } else { node.left }
            return IR {
                opcode: "Lsh",
                left: x,
                right: IR { opcode: "Const64", value: 1 },
                pos: node.pos
            }
        },
        priority: 2
    })
    
    
}

func (engine* rules_engine) register_expr_rules() void {
    
    engine.add_rule(rule {
        id: "and_self",
        name: "AND with self",
        matcher: func(node IR) bool {
            return node.opcode == "And" &&
                   ir_equals(node.left, node.right)
        },
        transformer: func(node IR) IR {
            return node.left
        },
        priority: 2
    })
    
    
    engine.add_rule(rule {
        id: "or_self",
        name: "OR with self",
        matcher: func(node IR) bool {
            return node.opcode == "Or" &&
                   ir_equals(node.left, node.right)
        },
        transformer: func(node IR) IR {
            return node.left
        },
        priority: 2
    })
    
    
    engine.add_rule(rule {
        id: "xor_self",
        name: "XOR with self",
        matcher: func(node IR) bool {
            return node.opcode == "Xor" &&
                   ir_equals(node.left, node.right)
        },
        transformer: func(node IR) IR {
            return IR {
                opcode: "Const64",
                value: 0,
                pos: node.pos
            }
        },
        priority: 2
    })
}

func (engine* rules_engine) add_rule(r rule) void {
    engine.rules.push(r)
    
    
    
    
}

func (engine* rules_engine) apply_block(block* basic_block) int {
    let total_transforms := 0
    let max_iterations := 100  
    
    for iteration := 0; iteration < max_iterations; iteration++ {
        let changed_in_iteration := 0
        
        for _for_idx_243 := 0; _for_idx_243 < len(block.instructions); _for_idx_243++ {
            instruction := block.instructions[_for_idx_243]
            let original := instruction
            let transformed := false
            
            
            for _for_idx_248 := 0; _for_idx_248 < len(engine.rules); _for_idx_248++ {
                rule := engine.rules[_for_idx_248]
                if rule.matcher(instruction) {
                    let result := rule.transformer(instruction)
                    
                    if result != original {
                        replace_instruction(block, instruction, result)
                        changed_in_iteration++
                        total_transforms++
                        transformed = true
                        break  
                    }
                }
            }
            
            
            if transformed {
                
                
            }
        }
        
        if changed_in_iteration == 0 {
            break  
        }
    }
    
    return total_transforms
}

func (engine* rules_engine) apply_func(func* ir_func) int {
    let total := 0
    
    for _for_idx_280 := 0; _for_idx_280 < len(func.blocks); _for_idx_280++ {
        block := func.blocks[_for_idx_280]
        total += engine.apply_block(block)
    }
    
    return total
}

func ir_equals(a, b IR) bool {
    if a.opcode != b.opcode {
        return false
    }
    
    if a.opcode == "Const64" {
        return a.value == b.value
    }
    
    
    return a.id == b.id  
}

func replace_instruction(block* basic_block, old_instr, new_instr IR) void {
    for i := 0; i < len(block.instructions); i++ {
        instr := block.instructions[i]
        if instr == old_instr {
            block.instructions[i] = new_instr
            return
        }
    }
}

func main() void {
    
    let engine := rules_engine{}
    engine.init()
    
    
    let ir := IR {
        opcode: "Add",
        left: IR { opcode: "Const64", value: 5 },
        right: IR { opcode: "Const64", value: 3 },
        pos: 0
    }
    
    let mut block := basic_block {
        instructions: vec(ir)
    }
    
    let transformed_count := engine.apply_block(&block)
    
    
    print("Transformed: ${transformed_count} instructions")
    print("Result: ${block.instructions[0]}")
}
