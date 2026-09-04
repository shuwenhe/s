package cmd.compile.internal.ssa

use std.vec.vec
use std.string

struct ssa_rule {
    string name
    string pattern
    string replacement
    int priority
    int benefit_estimate
    bool requires_liveness
}

struct rule_context {
    instr: ssa_instr_ptr
    operands: ssa_value_ptr[]
    config: compile_config
}

enum optimization_category {
    const_fold,
    algebraic_simp,
    condition_opt,
    cse,
    licm,
    gvn,
    dce,
    ccp,
}

func load_generic_rules() ssa_rule[] {
    rules := vec()
    
    rules.push_all(get_const_fold_rules())
    rules.push_all(get_algebraic_simp_rules())
    rules.push_all(get_condition_opt_rules())
    rules.push_all(get_cse_rules())
    
    return rules
}

func get_const_fold_rules() ssa_rule[] {
    rules := vec()
    
    rules.push(ssa_rule{
        name: "const_fold_add",
        pattern: "(Add (Const a) (Const b))",
        replacement: "(Const (add a b))",
        priority: 100,
        benefit_estimate: 10,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "const_fold_sub",
        pattern: "(Sub (Const a) (Const b))",
        replacement: "(Const (sub a b))",
        priority: 100,
        benefit_estimate: 10,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "const_fold_mul",
        pattern: "(Mul (Const a) (Const b))",
        replacement: "(Const (mul a b))",
        priority: 100,
        benefit_estimate: 10,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "const_fold_div",
        pattern: "(Div (Const a) (Const b))",
        replacement: "(Const (div a b))",
        priority: 100,
        benefit_estimate: 10,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "const_fold_and",
        pattern: "(And (Const a) (Const b))",
        replacement: "(Const (and a b))",
        priority: 95,
        benefit_estimate: 9,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "const_fold_or",
        pattern: "(Or (Const a) (Const b))",
        replacement: "(Const (or a b))",
        priority: 95,
        benefit_estimate: 9,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "const_fold_xor",
        pattern: "(Xor (Const a) (Const b))",
        replacement: "(Const (xor a b))",
        priority: 95,
        benefit_estimate: 9,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "const_fold_shl",
        pattern: "(Shl (Const a) (Const b))",
        replacement: "(Const (shl a b))",
        priority: 90,
        benefit_estimate: 8,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "const_fold_shr",
        pattern: "(Shr (Const a) (Const b))",
        replacement: "(Const (shr a b))",
        priority: 90,
        benefit_estimate: 8,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "const_fold_cmp_eq",
        pattern: "(Eq (Const a) (Const b))",
        replacement: "(Const (if a == b then 1 else 0))",
        priority: 85,
        benefit_estimate: 8,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "const_fold_cmp_ne",
        pattern: "(Ne (Const a) (Const b))",
        replacement: "(Const (if a != b then 1 else 0))",
        priority: 85,
        benefit_estimate: 8,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "const_fold_cmp_lt",
        pattern: "(Lt (Const a) (Const b))",
        replacement: "(Const (if a < b then 1 else 0))",
        priority: 85,
        benefit_estimate: 8,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "const_fold_cmp_le",
        pattern: "(Le (Const a) (Const b))",
        replacement: "(Const (if a <= b then 1 else 0))",
        priority: 85,
        benefit_estimate: 8,
        requires_liveness: false,
    })
    
    return rules
}

func get_algebraic_simp_rules() ssa_rule[] {
    rules := vec()
    
    rules.push(ssa_rule{
        name: "add_zero_left",
        pattern: "(Add (Const 0) x)",
        replacement: "x",
        priority: 80,
        benefit_estimate: 3,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "add_zero_right",
        pattern: "(Add x (Const 0))",
        replacement: "x",
        priority: 80,
        benefit_estimate: 3,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "mul_zero_left",
        pattern: "(Mul (Const 0) x)",
        replacement: "(Const 0)",
        priority: 80,
        benefit_estimate: 5,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "mul_zero_right",
        pattern: "(Mul x (Const 0))",
        replacement: "(Const 0)",
        priority: 80,
        benefit_estimate: 5,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "mul_one_left",
        pattern: "(Mul (Const 1) x)",
        replacement: "x",
        priority: 75,
        benefit_estimate: 3,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "mul_one_right",
        pattern: "(Mul x (Const 1))",
        replacement: "x",
        priority: 75,
        benefit_estimate: 3,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "mul_power_of_two_to_shl",
        pattern: "(Mul x (Const 2^n))",
        replacement: "(Shl x (Const n))",
        priority: 70,
        benefit_estimate: 4,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "div_one",
        pattern: "(Div x (Const 1))",
        replacement: "x",
        priority: 75,
        benefit_estimate: 3,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "div_power_of_two_to_shr",
        pattern: "(Div x (Const 2^n))",
        replacement: "(Shr x (Const n))",
        priority: 70,
        benefit_estimate: 4,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "and_self",
        pattern: "(And x x)",
        replacement: "x",
        priority: 75,
        benefit_estimate: 2,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "and_all_ones",
        pattern: "(And x (Const -1))",
        replacement: "x",
        priority: 75,
        benefit_estimate: 2,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "and_all_zeros",
        pattern: "(And x (Const 0))",
        replacement: "(Const 0)",
        priority: 75,
        benefit_estimate: 3,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "or_self",
        pattern: "(Or x x)",
        replacement: "x",
        priority: 75,
        benefit_estimate: 2,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "or_all_zeros",
        pattern: "(Or x (Const 0))",
        replacement: "x",
        priority: 75,
        benefit_estimate: 2,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "or_all_ones",
        pattern: "(Or x (Const -1))",
        replacement: "(Const -1)",
        priority: 75,
        benefit_estimate: 2,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "xor_self",
        pattern: "(Xor x x)",
        replacement: "(Const 0)",
        priority: 75,
        benefit_estimate: 2,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "xor_zeros",
        pattern: "(Xor x (Const 0))",
        replacement: "x",
        priority: 75,
        benefit_estimate: 2,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "sub_zero",
        pattern: "(Sub x (Const 0))",
        replacement: "x",
        priority: 75,
        benefit_estimate: 2,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "neg_neg",
        pattern: "(Neg (Neg x))",
        replacement: "x",
        priority: 70,
        benefit_estimate: 2,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "not_not",
        pattern: "(Not (Not x))",
        replacement: "x",
        priority: 70,
        benefit_estimate: 2,
        requires_liveness: false,
    })
    
    return rules
}

func get_condition_opt_rules() ssa_rule[] {
    rules := vec()
    
    rules.push(ssa_rule{
        name: "cond_branch_true",
        pattern: "if (Const true) then A else B",
        replacement: "A",
        priority: 90,
        benefit_estimate: 10,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "cond_branch_false",
        pattern: "if (Const false) then A else B",
        replacement: "B",
        priority: 90,
        benefit_estimate: 10,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "cond_branch_same",
        pattern: "if C then A else A",
        replacement: "A",
        priority: 85,
        benefit_estimate: 8,
        requires_liveness: false,
    })
    
    rules.push(ssa_rule{
        name: "cond_branch_not",
        pattern: "if (Not C) then A else B",
        replacement: "if C then B else A",
        priority: 60,
        benefit_estimate: 1,
        requires_liveness: false,
    })
    
    return rules
}

func get_cse_rules() ssa_rule[] {
    rules := vec()
    
    rules.push(ssa_rule{
        name: "cse_redundant_load",
        pattern: "(Load ptr) (Load ptr)",
        replacement: "复用第一个结果",
        priority: 70,
        benefit_estimate: 8,
        requires_liveness: true,
    })
    
    rules.push(ssa_rule{
        name: "cse_redundant_computation",
        pattern: "x := A; y := A",
        replacement: "x := A; y := x",
        priority: 70,
        benefit_estimate: 6,
        requires_liveness: true,
    })
    
    return rules
}

func get_licm_rules() ssa_rule[] {
    rules := vec()
    
    rules.push(ssa_rule{
        name: "licm_loop_invariant",
        pattern: "for { x := A } 其中 A 不依赖循环变量",
        replacement: "x := A; for { }",
        priority: 65,
        benefit_estimate: 15,
        requires_liveness: true,
    })
    
    return rules
}

func get_gvn_rules() ssa_rule[] {
    rules := vec()
    
    rules.push(ssa_rule{
        name: "gvn_redundant_expr",
        pattern: "x := a + b; y := a + b",
        replacement: "x := a + b; y := x",
        priority: 70,
        benefit_estimate: 8,
        requires_liveness: true,
    })
    
    return rules
}

func get_dce_rules() ssa_rule[] {
    rules := vec()
    
    rules.push(ssa_rule{
        name: "dce_unused_instr",
        pattern: "x := ... 其中 x 从不使用",
        replacement: "删除该指令",
        priority: 75,
        benefit_estimate: 5,
        requires_liveness: true,
    })
    
    return rules
}

struct ssa_optimizer {
    rules: ssa_rule[]
    stats: optimization_stats
}

struct optimization_stats {
    string pass_name
    int64 instructions_before
    int64 instructions_after
    int64 time_us
    float reduction_ratio
}

func (opt: &mut ssa_optimizer) run_optimization(ssa: &mut ssa_function) () {
    stats_before := opt.count_instructions(ssa)
    
    start_time := now_ns()
    
    for _for_idx_480 := 0; _for_idx_480 < len(opt.rules); _for_idx_480++ {
        rule := opt.rules[_for_idx_480]
        opt.apply_rule(ssa, rule)
    }
    
    stats_after := opt.count_instructions(ssa)
    
    elapsed_us := (now_ns() - start_time) / 1000
    
    opt.stats = optimization_stats{
        pass_name: "generic_optimization",
        instructions_before: stats_before,
        instructions_after: stats_after,
        time_us: elapsed_us,
        reduction_ratio: float(stats_after) / float(stats_before),
    }
}

func (opt: &mut ssa_optimizer) apply_rule(ssa: &mut ssa_function, rule: ssa_rule) () {
    for _for_idx_498 := 0; _for_idx_498 < len(ssa.blocks); _for_idx_498++ {
        block := ssa.blocks[_for_idx_498]
        for _for_idx_499 := 0; _for_idx_499 < len(block.instrs); _for_idx_499++ {
            instr := block.instrs[_for_idx_499]
            if opt.matches_pattern(instr, rule.pattern) {
                opt.apply_replacement(instr, rule.replacement)
            }
        }
    }
}

func (opt: &ssa_optimizer) matches_pattern(instr: ssa_instr_ptr, pattern: string) bool {
    return false
}

func (opt: &mut ssa_optimizer) apply_replacement(instr: ssa_instr_ptr, replacement: string) () {
}

func (opt: &ssa_optimizer) count_instructions(ssa: &ssa_function) int64 {
    count: int64 = 0
    for _for_idx_516 := 0; _for_idx_516 < len(ssa.blocks); _for_idx_516++ {
        block := ssa.blocks[_for_idx_516]
        count += block.instrs.len()
    }
    return count
}

func create_ssa_optimizer() ssa_optimizer {
    return ssa_optimizer{
        rules: load_generic_rules(),
        stats: optimization_stats{
            pass_name: "",
            instructions_before: 0,
            instructions_after: 0,
            time_us: 0,
            reduction_ratio: 1.0,
        },
    }
}
