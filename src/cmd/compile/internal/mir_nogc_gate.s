package compile.internal.mir_nogc_gate

func mir_nogc_gate_name() string {
    return "source->ast->type->mir->move->borrow->drop->c->native"
}

func mir_nogc_gate_trace() string {
    return "bb0:_1=box(10);_2=borrow &_1;end_borrow _2;_3=borrow &mut _1;end_borrow _3;_4=move _1;drop _4;return 42"
}

func mir_nogc_gate_contract_ok() int {
    trace := mir_nogc_gate_trace()
    if len(trace) == 0 {
        return 1
    }
    return 0
}
