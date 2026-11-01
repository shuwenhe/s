package compile.internal.ownership.analysis

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

enum ownership_decision_kind {
    accept,
    reject,
}

enum ownership_operation_kind {
    move,
    borrow_shared,
    borrow_mut,
    use_op,
    assign,
}

enum ownership_decision_reason {
    none,
    live_loan_conflict,
}

struct ownership_decision {
    ownership_decision_kind kind
    ownership_operation_kind operation
    ownership_decision_reason reason
}

struct old_ownership_observation {
    ownership_decision decision
    int source_pos
}

struct shadow_ownership_observation {
    ownership_decision decision
    int mir_point_id
}

struct ownership_decision_diff {
    string operation_id
    old_ownership_observation old
    shadow_ownership_observation shadow
    bool match
}

