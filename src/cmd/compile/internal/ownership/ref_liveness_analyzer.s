package ref_liveness_analyzer


struct cfg_block {
    int id
    string name
    vec[int] successors
    vec[string] uses
    vec[string] defs
}

struct cfg {
    vec[cfg_block] blocks
    map[int]cfg_block block_by_id
}

struct block_liveness {
    int block_id
    map[string]bool live_in
    map[string]bool live_out
}


func build_cfg_test1() cfg {
    c := cfg{}

    block0 := cfg_block{
        id: 0,
        name: "entry",
        successors: vec[int]{},
        uses: vec[string]{ "r" },
        defs: vec[string]{ "r", "r2" },
    }

    c.blocks = vec[cfg_block]{ block0 }
    c.block_by_id = map[int]cfg_block{}
    c.block_by_id[0] = block0

    return c
}


func build_cfg_test2() cfg {
    c := cfg{}

    block0 := cfg_block{
        id: 0,
        name: "entry",
        successors: vec[int]{},
        uses: vec[string]{ "r" },
        defs: vec[string]{ "r", "r2" },
    }

    c.blocks = vec[cfg_block]{ block0 }
    c.block_by_id = map[int]cfg_block{}
    c.block_by_id[0] = block0

    return c
}


func build_cfg_test3() cfg {
    c := cfg{}

    block0 := cfg_block{
        id: 0,
        name: "entry",
        successors: vec[int]{ 1, 2 },
        uses: vec[string]{ "r" },
        defs: vec[string]{ "r" },
    }

    block1 := cfg_block{
        id: 1,
        name: "if_true",
        successors: vec[int]{ 3 },
        uses: vec[string]{ "r" },
        defs: vec[string]{},
    }

    block2 := cfg_block{
        id: 2,
        name: "if_false",
        successors: vec[int]{ 3 },
        uses: vec[string]{},
        defs: vec[string]{},
    }

    block3 := cfg_block{
        id: 3,
        name: "join",
        successors: vec[int]{},
        uses: vec[string]{},
        defs: vec[string]{ "r2" },
    }

    c.blocks = vec[cfg_block]{ block0, block1, block2, block3 }
    c.block_by_id = map[int]cfg_block{}
    c.block_by_id[0] = block0
    c.block_by_id[1] = block1
    c.block_by_id[2] = block2
    c.block_by_id[3] = block3

    return c
}


func build_cfg_test4() cfg {
    c := cfg{}

    block0 := cfg_block{
        id: 0,
        name: "entry",
        successors: vec[int]{ 1, 2 },
        uses: vec[string]{ "r" },
        defs: vec[string]{ "r" },
    }

    block1 := cfg_block{
        id: 1,
        name: "if_true",
        successors: vec[int]{ 3 },
        uses: vec[string]{ "r" },
        defs: vec[string]{},
    }

    block2 := cfg_block{
        id: 2,
        name: "if_false",
        successors: vec[int]{ 3 },
        uses: vec[string]{},
        defs: vec[string]{},
    }

    block3 := cfg_block{
        id: 3,
        name: "join",
        successors: vec[int]{},
        uses: vec[string]{ "r" },
        defs: vec[string]{ "r2" },
    }

    c.blocks = vec[cfg_block]{ block0, block1, block2, block3 }
    c.block_by_id = map[int]cfg_block{}
    c.block_by_id[0] = block0
    c.block_by_id[1] = block1
    c.block_by_id[2] = block2
    c.block_by_id[3] = block3

    return c
}


func build_cfg_test5() cfg {
    c := cfg{}

    block0 := cfg_block{
        id: 0,
        name: "entry",
        successors: vec[int]{ 1 },
        uses: vec[string]{ "r" },
        defs: vec[string]{ "r" },
    }

    block1 := cfg_block{
        id: 1,
        name: "loop_header",
        successors: vec[int]{ 2, 3 },
        uses: vec[string]{ "r" },
        defs: vec[string]{},
    }

    block2 := cfg_block{
        id: 2,
        name: "loop_body",
        successors: vec[int]{ 1 },
        uses: vec[string]{},
        defs: vec[string]{},
    }

    block3 := cfg_block{
        id: 3,
        name: "exit",
        successors: vec[int]{},
        uses: vec[string]{},
        defs: vec[string]{ "r2" },
    }

    c.blocks = vec[cfg_block]{ block0, block1, block2, block3 }
    c.block_by_id = map[int]cfg_block{}
    c.block_by_id[0] = block0
    c.block_by_id[1] = block1
    c.block_by_id[2] = block2
    c.block_by_id[3] = block3

    return c
}


func build_cfg_test6() cfg {
    c := cfg{}

    block0 := cfg_block{
        id: 0,
        name: "entry",
        successors: vec[int]{},
        uses: vec[string]{ "r" },
        defs: vec[string]{ "r", "r2" },
    }

    c.blocks = vec[cfg_block]{ block0 }
    c.block_by_id = map[int]cfg_block{}
    c.block_by_id[0] = block0

    return c
}


func compute_liveness(c cfg) map[int]block_liveness {
    result := map[int]block_liveness{}


    for i := 0; i < len(c.blocks); i = i + 1 {
        block := c.blocks[i]
        result[block.id] = block_liveness{
            block_id: block.id,
            live_in: map[string]bool{},
            live_out: map[string]bool{},
        }
    }


    for iteration := 0; iteration < 20; iteration = iteration + 1 {
        changed := false


        for block_idx := len(c.blocks) - 1; block_idx >= 0; block_idx = block_idx - 1 {
            block := c.blocks[block_idx]
            old := result[block.id]


            new_live_out := map[string]bool{}
            for succ_idx := 0; succ_idx < len(block.successors); succ_idx = succ_idx + 1 {
                succ_id := block.successors[succ_idx]
                succ_liveness := result[succ_id]


                for ref_name, is_live := range succ_liveness.live_in {
                    if is_live {
                        new_live_out[ref_name] = true
                    }
                }
            }


            new_live_in := map[string]bool{}


            for use_idx := 0; use_idx < len(block.uses); use_idx = use_idx + 1 {
                new_live_in[block.uses[use_idx]] = true
            }


            for ref_name, is_live := range new_live_out {

                is_def := false
                for def_idx := 0; def_idx < len(block.defs); def_idx = def_idx + 1 {
                    if block.defs[def_idx] == ref_name {
                        is_def = true
                        break
                    }
                }

                if !is_def && is_live {
                    new_live_in[ref_name] = true
                }
            }


            if !maps_equal_bool(new_live_in, old.live_in) ||
               !maps_equal_bool(new_live_out, old.live_out) {
                changed = true
                old.live_in = new_live_in
                old.live_out = new_live_out
                result[block.id] = old
            }
        }

        if !changed {
            break
        }
    }

    return result
}


func maps_equal_bool(m1 map[string]bool, m2 map[string]bool) bool {

    for key, val := range m1 {
        if m2[key] != val {
            return false
        }
    }


    for key, val := range m2 {
        if m1[key] != val {
            return false
        }
    }

    return true
}


func validate_test(test_id int, liveness map[int]block_liveness) string {
    if test_id == 1 {
        return validate_test1(liveness)
    } else if test_id == 2 {
        return validate_test2(liveness)
    } else if test_id == 3 {
        return validate_test3(liveness)
    } else if test_id == 4 {
        return validate_test4(liveness)
    } else if test_id == 5 {
        return validate_test5(liveness)
    } else if test_id == 6 {
        return validate_test6(liveness)
    }

    return "ERROR"
}


func validate_test1(liveness map[int]block_liveness) string {

    block0 := liveness[0]


    if block0.live_out["r"] {
        return "CONFLICT"
    }

    return "ALLOW"
}


func validate_test2(liveness map[int]block_liveness) string {


    block0 := liveness[0]

    if block0.live_in["r"] {
        return "CONFLICT"
    }

    return "ALLOW"
}


func validate_test3(liveness map[int]block_liveness) string {


    block3 := liveness[3]

    if block3.live_in["r"] {
        return "CONFLICT"
    }

    return "ALLOW"
}


func validate_test4(liveness map[int]block_liveness) string {

    block3 := liveness[3]

    if block3.live_in["r"] {
        return "CONFLICT"
    }

    return "ALLOW"
}


func validate_test5(liveness map[int]block_liveness) string {

    block3 := liveness[3]

    if block3.live_in["r"] {
        return "CONFLICT"
    }

    return "ALLOW"
}


func validate_test6(liveness map[int]block_liveness) string {


    return "ALLOW"
}


func analyze_and_report(test_id int) string {
    cfg := simple_cfg{}

    if test_id == 1 {
        cfg = build_cfg_test1()
    } else if test_id == 2 {
        cfg = build_cfg_test2()
    } else if test_id == 3 {
        cfg = build_cfg_test3()
    } else if test_id == 4 {
        cfg = build_cfg_test4()
    } else if test_id == 5 {
        cfg = build_cfg_test5()
    } else if test_id == 6 {
        cfg = build_cfg_test6()
    }

    liveness := compute_liveness(cfg)
    return validate_test(test_id, liveness)
}
