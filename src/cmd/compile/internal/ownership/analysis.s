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
