package compile.internal.ownership.analysis

// Type definitions for ownership liveness analysis
// NOTE: Implementation currently in compiler.s (single authority)
// This module marks the logical boundary for future modularization
// See: compiler.s line 3865 analyze_ownership_liveness()

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

// ===== C.3.1a: Decision Model Types (Pure Semantics) =====
// NOTE: Decision semantics are separated from point identity (s.pos vs MIR point).
// Decisions are wrapped in separate observation types that carry point metadata.
// See: /memories/repo/c3_1_differential_authority_gate_2026_09_17.md

enum ownership_decision_kind {
    accept
    reject
}

enum ownership_operation_kind {
    move
    borrow_shared
    borrow_mut
    use
    assign
}

enum ownership_decision_reason {
    none
    live_loan_conflict
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

// ===== C.3.1b.1: Loan Liveness Query (Pure Query, No Logic) =====
// NOTE: This is a pure query function - no side effects, no solver mutation
// Input: analysis (from solver), loan_id, point_id (both canonical MIR identifiers)
// Output: bool (is this loan live at this point?)
// Constraint: No Place, no conflict checking, no Decision making, no s.pos

func analysis_loan_live_at(
    ownership_analysis* analysis,
    int loan_id,
    int point_id
) bool {
    // Validate inputs (return false for invalid, never fail/error)
    if analysis == nil {
        return false
    }
    if loan_id < 0 || loan_id >= len(analysis.loan_live_points) {
        return false
    }
    if point_id < 0 || point_id >= 31 {  // 30-bit point capacity (P0..P30, 31 points total)
        return false
    }
    
    // Query: is point_id's bit set in loan_id's liveness mask?
    // Representation: each loan_live_points[i] is a 32-bit integer bitmask
    // bit N set means loan i is live at point N
    mask := 1 << point_id
    return (analysis.loan_live_points[loan_id] & mask) != 0
}
