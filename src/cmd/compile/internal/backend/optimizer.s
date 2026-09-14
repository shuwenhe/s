package backend
struct optimizer {
    prog_list* prog
    int pass_count
}

func make_optimizer(prog_list* prog) optimizer {
    opt: optimizer
    opt.prog = prog
    opt.pass_count = 0
    opt
}

func (opt* optimizer) remove_dead_code() {
    changed := true
    for changed {
        changed = false
        p := opt.prog.first()
        for p != nil {
            next_p := p.next
            if p.op == prog_op_nop() {
                opt.prog.remove_prog(p)
                changed = true
            }
            p = next_p
        }
    }
    opt.pass_count = opt.pass_count + 1
}

func (opt* optimizer) combine_redundant_moves() {
    p := opt.prog.first()
    for p != nil && p.next != nil {
        curr := p
        next_p := p.next
        if curr.op == prog_op_mov() && next_p.op == prog_op_mov() {
            if curr.as_string == next_p.as_string {
                opt.prog.remove_prog(next_p)
            }
        }
        p = p.next
    }
    opt.pass_count = opt.pass_count + 1
}

func (opt* optimizer) remove_redundant_pushes() {
    p := opt.prog.first()
    for p != nil && p.next != nil {
        curr := p
        next_p := p.next
        if curr.op == prog_op_push() && next_p.op == prog_op_pop() {
            opt.prog.remove_prog(curr)
            opt.prog.remove_prog(next_p)
        }
        p = p.next
    }
    opt.pass_count = opt.pass_count + 1
}

func (opt* optimizer) optimize_constant_folding() {
    p := opt.prog.first()
    for p != nil {
        if p.op == prog_op_add() || p.op == prog_op_sub() || p.op == prog_op_mul() {
        }
        p = p.next
    }
    opt.pass_count = opt.pass_count + 1
}

func (opt* optimizer) optimize_register_moves() {
    p := opt.prog.first()
    for p != nil && p.next != nil {
        curr := p
        next_p := p.next
        if curr.op == prog_op_mov() {
        }
        p = p.next
    }
    opt.pass_count = opt.pass_count + 1
}

func (opt* optimizer) run_optimization_passes() {
    opt.remove_dead_code()
    opt.combine_redundant_moves()
    opt.remove_redundant_pushes()
    opt.optimize_constant_folding()
    opt.optimize_register_moves()
}

func (opt* optimizer) get_optimized_prog() prog_list {
    *opt.prog
}
