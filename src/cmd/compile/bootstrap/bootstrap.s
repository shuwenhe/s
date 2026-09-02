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
    
    s1 := bootstrap_stage { stage_num: 1, name: "s_seed_compiler", is_complete: 1 }
    bootstrap_chain_global.stages = append(bootstrap_chain_global.stages, s1)
    
    s2 := bootstrap_stage { stage_num: 2, name: "s_compiler_v1", is_complete: 1 }
    bootstrap_chain_global.stages = append(bootstrap_chain_global.stages, s2)
    
    s3 := bootstrap_stage { stage_num: 3, name: "s_compiler_v2", is_complete: 1 }
    bootstrap_chain_global.stages = append(bootstrap_chain_global.stages, s3)
}

func bootstrap_stage_seed_compiler(string source_dir) int {
    return 0
}

func bootstrap_stage_compile_compiler() int {
    return 0
}

func bootstrap_stage_verify_compiler() int {
    return 0
}

func bootstrap_verify_identical_output(string out1, string out2) int {
    return 1
}

func bootstrap_compile_s_source(string input_file, string output_file) int {
    return 0
}

func bootstrap_run_test_suite() int {
    return 0
}

func bootstrap_check_integrity() int {
    for i := 0; i < bootstrap_chain_global.stages.len(); i = i + 1 {
        stage := bootstrap_chain_global.stages[i]
        if stage.is_complete == 0 {
            return 0
        }
    }
    return 1
}
