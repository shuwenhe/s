package compile.compiler
extern "intrinsic" func host_args() string[];
extern "intrinsic" func __host_read_to_string(string path) string;
extern "intrinsic" func __host_write_text_file(string path, string contents) int;
extern "intrinsic" func runtime_env_get(string key, string fallback) string;
extern "intrinsic" func __host_char_at(string text, int index) string;
extern "intrinsic" func __host_slice(string text, int start, int end) string;

struct compiler_state {
    string source
    int pos
    int line
    string token
    string error
    string code
    string[] names
    int[] kinds
    int[] live
    int[] roots
    int[] parents
    int[] loan_fields
    int[] loan_parent_fields
    int[] array_lengths
    int[] struct_ids
    int[] field_state
    int[] field_borrow_state
    int[] nested_field_state
    int[] nested_field_borrow_state
    int count
    int loop_floor
    int loop_cleanup
    int depth
    int expr_depth
    int terminated
    string value
    int value_kind
    int value_slot
    int value_parent
    int value_field
    int value_parent_field
    int value_array_length
    int value_struct_id
    bool new_borrow
    string[] function_names
    string[] function_declaration_refs
    int[] function_counts
    int[] function_returns
    string[] function_return_constants
    string[] function_return_call_targets
    string[] function_branch_conditions
    string[] function_branch_true_constants
    string[] function_branch_false_constants
    string pending_branch_condition
    string pending_branch_true_constant
    int[] function_return_params
    int return_kind
    int parameter_count
    int return_param
    int[] function_starts
    int[] function_param_kinds
    int[] function_param_structs
    int[] function_return_structs
    int[] function_observed_return_kinds
    int[] function_observed_return_structs
    string[] function_observed_compat
    int function_count
    int function_param_total
    string[] struct_names
    string[] struct_field_lefts
    string[] struct_field_rights
    int[] struct_field_left_kinds
    int[] struct_field_right_kinds
    string[] struct_field_names
    int[] struct_field_kinds
    int[] struct_field_structs
    int[] struct_field_starts
    int[] struct_field_counts
    int[] struct_custom_drops
    int struct_count
    string function_name
    bool function_main
    string[] method_names
    int[] method_structs
    int[] method_returns
    int method_count
    string stage7_compatibility_actual_source
    string stage7_compatibility_expected_source
    string stage7_compatibility_expected_key
    string stage7_compatibility_result
    string stage7_compatibility_action
    string stage7_compatibility_name_reresolution
    string stage7_compatibility_declaration_ref
    string stage7_rejection_source
    string stage7_rejection_kind
    string stage7_rejection_diagnostic
    string stage7_rejection_expected_key
    string stage7_rejection_name_reresolution
}


struct compiler_stage8_canonical_type_ref_output {
    string stage7_type_fact
    string producer
    string canonical_type_ref
    string output_carrier
    bool readable
    bool stage9_consumable
}

struct canonical_frontend_result {
    bool ok
    string function_name
    string declaration_ref
    string type_fact
    string canonical_type_ref
    string output_carrier
}

struct compiler_stage9_semantic_consumer_result {
    bool consumed
    string input_authority
    string canonical_type_ref
    string canonical_reconstruction
}

struct compiler_stage10_mir_lowering_result {
    bool consumed
    string input_authority
    string semantic_reconstruction
    string mir_output
    string output_carrier
    bool readable
    bool stage11_consumable
}

struct compiler_stage11_mir_verification_result {
    bool consumed
    string input_authority
    string mir_reconstruction
    string evidence
}

struct compiler_stage12_mir_input_boundary {
    bool consumed
    string input_authority
    string mir_reconstruction
    string evidence
}

struct ownership_decision {
    bool allowed
    int loan_id
    int point_id
    int conflict_place
    bool legacy_allowed
}

struct ownership_analysis_input {
    int point_count
    int[] ref_seen
    int[] ref_loans
    int[] region_points
    int[] loan_points
    int[] outlives_from
    int[] outlives_to
    int outlives_count
    int loan_count
}

struct ownership_analysis {
    int[] region_live_points
    int[] loan_live_points
    int iterations
    bool converged
}

