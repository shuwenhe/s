package backend
struct prog_op {
    string name
    int code
}

struct prog {
    int id
    int op
    prog* prev
    prog* next
    string as_string
    int lineno
}

struct prog_list {
    prog* head
    prog* tail
    int count
}

func prog_op_mov() int { 0 }

func prog_op_add() int { 1 }

func prog_op_sub() int { 2 }

func prog_op_mul() int { 3 }

func prog_op_div() int { 4 }

func prog_op_and() int { 5 }

func prog_op_or() int { 6 }

func prog_op_xor() int { 7 }

func prog_op_cmp() int { 8 }

func prog_op_jmp() int { 9 }

func prog_op_jne() int { 10 }

func prog_op_je() int { 11 }

func prog_op_call() int { 12 }

func prog_op_ret() int { 13 }

func prog_op_push() int { 14 }

func prog_op_pop() int { 15 }

func prog_op_lea() int { 16 }

func prog_op_load() int { 17 }

func prog_op_store() int { 18 }

func prog_op_nop() int { 19 }

func prog_op_test() int { 20 }

func prog_op_shl() int { 21 }

func prog_op_shr() int { 22 }

func make_prog_list() prog_list {
    prog_list { nil, nil, 0 }
}

func (pl* prog_list) append_prog(int op, string as_string) {
    p := &prog { pl.count, op, pl.tail, nil, as_string, 0 }
    if pl.tail != nil {
        pl.tail.next = p
    }
    if pl.head == nil {
        pl.head = p
    }
    pl.tail = p
    pl.count = pl.count + 1
}

func (pl* prog_list) append_prog_at_head(int op, string as_string) {
    p := &prog { pl.count, op, nil, pl.head, as_string, 0 }
    if pl.head != nil {
        pl.head.prev = p
    }
    if pl.tail == nil {
        pl.tail = p
    }
    pl.head = p
    pl.count = pl.count + 1
}

func (pl* prog_list) insert_after(prog* pos, int op, string as_string) {
    if pos == nil {
        pl.append_prog_at_head(op, as_string)
        return
    }
    p := &prog { pl.count, op, pos, pos.next, as_string, 0 }
    pos.next = p
    if p.next != nil {
        p.next.prev = p
    }
    if pl.tail == pos {
        pl.tail = p
    }
    pl.count = pl.count + 1
}

func (pl* prog_list) remove_prog(prog* p) {
    if p.prev != nil {
        p.prev.next = p.next
    } else {
        pl.head = p.next
    }
    if p.next != nil {
        p.next.prev = p.prev
    } else {
        pl.tail = p.prev
    }
    pl.count = pl.count - 1
}

func (pl* prog_list) first() prog* {
    pl.head
}

func (pl* prog_list) last() prog* {
    pl.tail
}

func (pl* prog_list) len() int {
    pl.count
}

func (pl* prog_list) dump() string {
    result := ""
    p := pl.head
    for p != nil {
        result = result + p.as_string + "\n"
        p = p.next
    }
    result
}

func op_name(int op) string {
    switch op {
        case 0 : "mov",
        case 1 : "add",
        case 2 : "sub",
        case 3 : "mul",
        case 4 : "div",
        case 5 : "and",
        case 6 : "or",
        case 7 : "xor",
        case 8 : "cmp",
        case 9 : "jmp",
        case 10 : "jne",
        case 11 : "je",
        case 12 : "call",
        case 13 : "ret",
        case 14 : "push",
        case 15 : "pop",
        case 16 : "lea",
        case 17 : "load",
        case 18 : "store",
        case 19 : "nop",
        case 20 : "test",
        case 21 : "shl",
        case 22 : "shr",
        default : "unknown"
    }
}
