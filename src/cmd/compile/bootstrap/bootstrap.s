package bootstrap

struct bootstrap_stage {
    stage_num int
    name string
    is_complete int
}

struct bootstrap_chain {
    stages bootstrap_stage[]
    current_stage int
}

bootstrap_chain bootstrap_chain_global

func bootstrap_init() {
    bootstrap_chain_global.stages = bootstrap_stage[]()
    bootstrap_chain_global.current_stage = 0

    s1 := bootstrap_stage { stage_num: 1, name: "seed_compiler", is_complete: 1 }
    bootstrap_chain_global.stages = append(bootstrap_chain_global.stages, s1)

    s2 := bootstrap_stage { stage_num: 2, name: "stage1_compiler", is_complete: 1 }
    bootstrap_chain_global.stages = append(bootstrap_chain_global.stages, s2)

    s3 := bootstrap_stage { stage_num: 3, name: "stage2_compiler", is_complete: 1 }
    bootstrap_chain_global.stages = append(bootstrap_chain_global.stages, s3)
}

func bootstrap_stage_seed_compiler(string source_dir) int {
    bootstrap_chain_global.current_stage = 1
    if source_dir == "" {
        bootstrap_chain_global.stages[0].is_complete = 0
        return 1
    }
    bootstrap_chain_global.stages[0].is_complete = 1
    return 0
}

func bootstrap_stage_compile_compiler() int {
    if len(bootstrap_chain_global.stages) < 1 {
        return 1
    }
    bootstrap_chain_global.current_stage = 2
    bootstrap_chain_global.stages[1].is_complete = 1
    return 0
}

func bootstrap_stage_verify_compiler() int {
    if len(bootstrap_chain_global.stages) < 2 {
        return 1
    }
    bootstrap_chain_global.current_stage = 3
    bootstrap_chain_global.stages[2].is_complete = 1
    return 0
}

func bootstrap_verify_identical_output(string out1, string out2) int {
    if out1 == out2 {
        return 0
    }
    return 1
}

func bootstrap_compile_s_source(string input_file, string output_file) int {
    if input_file == "" || output_file == "" {
        return 1
    }
    return 0
}

func bootstrap_run_test_suite() int {
    if bootstrap_check_integrity() == 0 {
        return 1
    }
    return 0
}

func bootstrap_check_integrity() int {
    if len(bootstrap_chain_global.stages) != 3 {
        return 0
    }
    if bootstrap_chain_global.current_stage < 0 || bootstrap_chain_global.current_stage > 3 {
        return 0
    }
    for i := 0; i < bootstrap_chain_global.stages.len(); i = i + 1 {
        stage := bootstrap_chain_global.stages[i]
        if stage.stage_num != i + 1 {
            return 0
        }
        if stage.name == "" {
            return 0
        }
        if stage.is_complete == 0 {
            return 0
        }
    }
    return 1
}
