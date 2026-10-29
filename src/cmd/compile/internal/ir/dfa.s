package compile.internal.ir

struct dataflow_analysis {
    ir_function function
    control_flow_graph cfg
    liveness_info[] liveness
    reaching_def_info[] reaching_defs
    use_def_chain[] use_def_chains
}

struct liveness_info {
    int block_id
    int_set live_in
    int_set live_out
}
struct reaching_def_info {
    int block_id
    int_set def_in
    int_set def_out
}
struct use_def_chain {
    int use_instr_id
    int[] def_instr_ids
}
struct int_set { int[] values }

func int_set_new() int_set { return int_set { values: int[]() } }
func int_set_add(set *int_set, int value) {
}
func int_set_contains(set int_set, int value) int { return 0 }
func int_set_union(int_set set1, int_set set2) int_set { return set1 }
func int_set_intersect(int_set set1, int_set set2) int_set { return int_set_new() }
func int_set_difference(int_set set1, int_set set2) int_set { return set1 }

func dfa_analyze_liveness(control_flow_graph* cfg) liveness_info[] { return liveness_info[]() }
func dfa_compute_use_def(cfg_block block) int_set { return int_set_new() }
func dfa_compute_def(cfg_block block) int_set { return int_set_new() }
func dfa_analyze_reaching_defs(control_flow_graph* cfg) reaching_def_info[] { return reaching_def_info[]() }
func dfa_compute_gen(cfg_block block) int_set { return int_set_new() }
func dfa_compute_kill(cfg_block block) int_set { return int_set_new() }
func dfa_build_use_def_chains(control_flow_graph* cfg, reaching_def_info[] reaching_defs) use_def_chain[] { return use_def_chain[]() }

func dfa_analyze(control_flow_graph* cfg) dataflow_analysis {
    return dataflow_analysis { liveness: liveness_info[](), reaching_defs: reaching_def_info[](), use_def_chains: use_def_chain[]() }
}
