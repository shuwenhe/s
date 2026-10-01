package ref_liveness_prototype

struct ref_occurrence {
    string ref_name
    int block_id
    int point_in_block
    string kind
}

struct simple_cfg {
    vec[simple_block] blocks
}

struct simple_block {
    int id
    string name
    vec[int] successors
    vec[ref_occurrence] occurrences
}

struct liveness_result {

    map[string]bool live_in_by_block
    map[string]bool live_out_by_block
}

func build_test1_cfg() simple_cfg {
    cfg := simple_cfg{}

    block0 := simple_block{
        id: 0,
        name: "entry",
        successors: vec[int]{},
        occurrences: vec[ref_occurrence]{
            ref_occurrence{ ref_name: "r", block_id: 0, point_in_block: 0, kind: "borrow" },
            ref_occurrence{ ref_name: "r", block_id: 0, point_in_block: 1, kind: "use" },
            ref_occurrence{ ref_name: "r2", block_id: 0, point_in_block: 2, kind: "reborrow" },
        },
    }

    cfg.blocks = vec[simple_block]{ block0 }
    return cfg
}

func build_test3_cfg() simple_cfg {
    cfg := simple_cfg{}

    block0 := simple_block{
        id: 0,
        name: "entry",
        successors: vec[int]{ 1, 2 },
        occurrences: vec[ref_occurrence]{
            ref_occurrence{ ref_name: "r", block_id: 0, point_in_block: 0, kind: "borrow" },
        },
    }

    block1 := simple_block{
        id: 1,
        name: "if_true",
        successors: vec[int]{ 3 },
        occurrences: vec[ref_occurrence]{
            ref_occurrence{ ref_name: "r", block_id: 1, point_in_block: 0, kind: "use" },
        },
    }

    block2 := simple_block{
        id: 2,
        name: "if_false",
        successors: vec[int]{ 3 },
        occurrences: vec[ref_occurrence]{},
    }

    block3 := simple_block{
        id: 3,
        name: "join",
        successors: vec[int]{},
        occurrences: vec[ref_occurrence]{
            ref_occurrence{ ref_name: "r2", block_id: 3, point_in_block: 0, kind: "reborrow" },
        },
    }

    cfg.blocks = vec[simple_block]{ block0, block1, block2, block3 }
    return cfg
}

func compute_simplified_liveness(cfg simple_cfg) {

    _ = cfg
}

func analyze_test_case(test_id int) string {
    cfg := simple_cfg{}

    if test_id == 1 {
        cfg = build_test1_cfg()
    } else if test_id == 3 {
        cfg = build_test3_cfg()
    }

    return "NOT_YET_IMPLEMENTED"
}
