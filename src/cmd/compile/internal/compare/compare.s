package compile.internal.compare
use std.slices

struct compare_field {
    string name
    int offset
    int size
    int alignment
    bool padded
    bool regular_memory
    bool can_panic
    string type_kind
    int num_elem
    int elem_cost
    bool elem_can_panic
}

struct compare_struct {
    compare_field[] fields
    int alignment
    int reg_size
    int arch_alignment
    bool can_merge_loads
}

struct memrun_result {
    int size
    int next
}

struct field_cost_result {
    int cost
    int size
    int next
}

struct compare_node {
    string expr
    bool is_call
}

struct eq_struct_result {
    compare_node[] conds
    bool can_panic
}

struct eq_string_result {
    string eqlen
    string eqmem
}

struct eq_interface_result {
    string eqtab
    string eqdata
}

struct eqmem_func_result {
    string name
    bool need_size
}

func is_regular_memory(compare_field field_value) bool {
    field_value.regular_memory
}

func memrun(compare_struct t, int start) memrun_result {
    next := start
    for true {
        next = next + 1
        if next >= len(t.fields) {
            break
        }
        if t.fields[next - 1].padded {
            break
        }
        f := t.fields[next]
        if f.name == "_" || !is_regular_memory(f) {
            break
        }
        if t.arch_alignment > 1 {
            align := t.alignment
            off := t.fields[start].offset
            if (off % align) != 0 {
                align = least_alignment(off)
            }
            size := field_end(t.fields[next]) - t.fields[start].offset
            if size > align {
                break
            }
        }
    }
    memrun_result {
        size: field_end(t.fields[next - 1]) - t.fields[start].offset,
        next: next,
    }
}

func eq_can_panic(compare_struct t) bool {
    i := 0
    for i < len(t.fields) {
        f := t.fields[i]
        if f.name != "_" && (f.can_panic || (f.type_kind == "array" && f.elem_can_panic)) {
            return true
        }
        i = i + 1
    }
    false
}

func eq_struct_cost(compare_struct t) int {
    cost := 0
    i := 0
    for i < len(t.fields) {
        f := t.fields[i]
        if f.name == "_" {
            i = i + 1
            continue
        }
        fc := eq_struct_field_cost(t, i)
        cost = cost + fc.cost
        i = fc.next
    }
    cost
}

func eq_struct_field_cost(compare_struct t, int i) field_cost_result {
    if t.can_merge_loads {
        run := memrun(t, i)
        cost := run.size / t.reg_size
        if (run.size % t.reg_size) != 0 {
            cost = cost + 1
        }
        return field_cost_result {
            cost: cost,
            size: run.size,
            next: run.next,
        }
    }
    f := t.fields[i]
    field_cost_result {
        cost: calculate_cost_for_field(f, t.reg_size),
        size: f.size,
        next: i + 1,
    }
}

func calculate_cost_for_field(compare_field f, int reg_size) int {
    if f.type_kind == "struct" {
        return f.elem_cost
    }
    if f.type_kind == "slice" {
        return 0
    }
    if f.type_kind == "array" {
        return f.num_elem * f.elem_cost
    }
    if f.type_kind == "string" || f.type_kind == "interface" || f.type_kind == "complex64" || f.type_kind == "complex128" {
        return 2
    }
    if f.type_kind == "int64" || f.type_kind == "uint64" {
        c := 8 / reg_size
        if c <= 0 {
            return 1
        }
        return c
    }
    1
}

func eq_struct(compare_struct t, string np, string nq) eq_struct_result {
    segments := compare_node[[]]()
    segments = append(segments, compare_node[]())
    i := 0
    for i < len(t.fields) {
        f := t.fields[i]
        if f.name == "_" {
            i = i + 1
            continue
        }
        type_can_panic := f.can_panic || (f.type_kind == "array" && f.elem_can_panic)
        if !f.regular_memory {
            if type_can_panic {
                segments = append(segments, compare_node[]())
            }
            if f.type_kind == "string" {
                sres := eq_string(np + "." + f.name, nq + "." + f.name)
                append_segment_node(segments, compare_node { expr: sres.eqlen, is_call: false })
                append_segment_node(segments, compare_node { expr: sres.eqmem, is_call: true })
            } else {
                append_segment_node(segments, compare_node {
                    expr: eq_field(np, nq, f.name),
                    is_call: false,
                })
            }
            if type_can_panic {
                segments = append(segments, compare_node[]())
            }
            i = i + 1
            continue
        }
        fc := eq_struct_field_cost(t, i)
        if fc.cost <= 4 {
            j := i
            for j < fc.next {
                fj := t.fields[j]
                append_segment_node(segments, compare_node {
                    expr: eq_field(np, nq, fj.name),
                    is_call: false,
                })
                j = j + 1
            }
        } else {
            append_segment_node(segments, compare_node {
                expr: eq_mem(np, nq, f.name, fc.size, f.alignment, t.arch_alignment, t.can_merge_loads),
                is_call: true,
            })
        }
        i = fc.next
    }
    flat := compare_node[]()
    s := 0
    for s < len(segments) {
        sorted := sort_calls_last(segments[s])
        k := 0
        for k < len(sorted) {
            flat = append(flat, sorted[k])
            k = k + 1
        }
        s = s + 1
    }
    eq_struct_result {
        conds: flat,
        can_panic: len(segments) > 1,
    }
}

func eq_string(string s, string t) eq_string_result {
    eq_string_result {
        eqlen: "len(" + s + ") == len(" + t + ")",
        eqmem: "memequal(sptr(" + s + "), sptr(" + t + "), len(" + s + "))",
    }
}

func eq_interface(string s, string t, bool is_empty_interface) eq_interface_result {
    fn_name := "ifaceeq"
    if is_empty_interface {
        fn_name = "efaceeq"
    }
    eq_interface_result {
        eqtab: "itab(" + s + ") == itab(" + t + ")",
        eqdata: fn_name + "(itab(" + s + "), idata(" + s + "), idata(" + t + "))",
    }
}

func eq_field(string p, string q, string field_name) string {
    p + "." + field_name + " == " + q + "." + field_name
}

func eq_mem(string p, string q, string field_name, int size, int alignment, int arch_alignment, bool can_merge_loads) string {
    plan := eq_mem_func(size, alignment, arch_alignment, can_merge_loads)
    if plan.need_size {
        return plan.name + "(&" + p + "." + field_name + ", &" + q + "." + field_name + ", " + to_string(size) + ")"
    }
    plan.name + "(&" + p + "." + field_name + ", &" + q + "." + field_name + ")"
}

func eq_mem_func(int size, int alignment, int arch_alignment, bool can_merge_loads) eqmem_func_result {
    if !can_merge_loads && alignment < arch_alignment && alignment < size {
        size = 0
    }
    if size == 1 {
        return eqmem_func_result { name: "memequal8", need_size: false }
    }
    if size == 2 {
        return eqmem_func_result { name: "memequal16", need_size: false }
    }
    if size == 4 {
        return eqmem_func_result { name: "memequal32", need_size: false }
    }
    if size == 8 {
        return eqmem_func_result { name: "memequal64", need_size: false }
    }
    if size == 16 {
        return eqmem_func_result { name: "memequal128", need_size: false }
    }
    eqmem_func_result { name: "memequal", need_size: true }
}

func append_segment_node(compare_node[[]] segments, compare_node node) () {
    if len(segments) == 0 {
        segments = append(segments, compare_node[]())
    }
    last := len(segments) - 1
    segments[last].push(node)
}

func sort_calls_last(compare_node[] nodes) compare_node[] {
    out := compare_node[]()
    i := 0
    for i < len(nodes) {
        if !nodes[i].is_call {
            out = append(out, nodes[i])
        }
        i = i + 1
    }
    i = 0
    for i < len(nodes) {
        if nodes[i].is_call {
            out = append(out, nodes[i])
        }
        i = i + 1
    }
    out
}

func field_end(compare_field f) int {
    f.offset + f.size
}

func least_alignment(int off) int {
    if off == 0 {
        return 1
    }
    v := off
    align := 1
    for (v % 2) == 0 {
        align = align * 2
        v = v / 2
    }
    align
}
