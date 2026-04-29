package compile.internal.compare

use std.vec.vec

func make_field(string name, int offset, int size, bool regular_memory, string type_kind) compare_field {
    compare_field {
        name: name,
        offset: offset,
        size: size,
        alignment: 1,
        padded: false,
        regular_memory: regular_memory,
        can_panic: type_kind == "interface",
        type_kind: type_kind,
        num_elem: 0,
        elem_cost: 1,
        elem_can_panic: false,
    }
}

func run_compare_tests() int {
    let fields = vec[compare_field]()
    fields.push(make_field("a", 0, 4, true, "int32"))
    fields.push(make_field("b", 4, 4, true, "int32"))
    fields.push(make_field("s", 8, 16, false, "string"))

    let t = compare_struct {
        fields: fields,
        alignment: 8,
        reg_size: 8,
        arch_alignment: 1,
        can_merge_loads: true,
    }

    if eq_struct_cost(t) != 3 {
        return 1
    }

    let sres = eq_string("x", "y")
    if sres.eqlen != "len(x) == len(y)" {
        return 1
    }

    let ires = eq_interface("a", "b", true)
    if ires.eqdata != "efaceeq(itab(a), idata(a), idata(b))" {
        return 1
    }

    let cmp = eq_struct(t, "p", "q")
    if cmp.conds.len() == 0 {
        return 1
    }

    let m16 = eq_mem_func(16, 8, 8, true)
    if m16.name != "memequal128" || m16.need_size {
        return 1
    }

    let md = eq_mem_func(24, 8, 8, true)
    if md.name != "memequal" || !md.need_size {
        return 1
    }

    0
}
