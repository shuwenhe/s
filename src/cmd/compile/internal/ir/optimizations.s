package compile.internal.ir

struct optimization_context {
    ir_module module
    control_flow_graph cfg
    dataflow_analysis dfa
    int changes
}

func run_optimization_pipeline(ir_module module) { return }
func apply_opt_constant_folding(control_flow_graph cfg) { return }
func opt_fold_constant(int op, string left, string right) string { return "" }
func apply_opt_dead_code_elimination(control_flow_graph cfg) { return }
func apply_opt_constant_propagation(control_flow_graph cfg) { return }
func apply_opt_global_value_numbering(control_flow_graph cfg) { return }
func opt_compute_instruction_signature(ir_instruction instr) string { return "" }
func make_string_value_map() string[] { return string[]() }
func make_string_instruction_map() ir_instruction[] { return ir_instruction[]() }
func apply_opt_licm(control_flow_graph cfg, loop_info[] loops) { return }
