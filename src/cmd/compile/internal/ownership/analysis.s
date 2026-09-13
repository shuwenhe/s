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

func analyze_ownership_liveness(ownership_analysis_input input) ownership_analysis {
    region_points := input.region_points
    loan_points := input.loan_points
    changed := true
    iterations := 0
    while changed && iterations < 16 {
        changed = false
        i := 0
        while i < input.outlives_count {
            from := input.outlives_from[i]
            to := input.outlives_to[i]
            before := region_points[from]
            region_points[from] = ownership_region_union_value(region_points[from], region_points[to])
            if region_points[from] != before { changed = true }
            i = i + 1
        }
        i = 0
        while i < len(input.ref_seen) {
            loan := input.ref_loans[i]
            if input.ref_seen[i] != 0 && loan >= 0 {
                before_loan := loan_points[loan]
                loan_points[loan] = ownership_region_union_value(loan_points[loan], region_points[i])
                if loan_points[loan] != before_loan { changed = true }
            }
            i = i + 1
        }
        iterations = iterations + 1
    }
    ownership_analysis { region_live_points: region_points, loan_live_points: loan_points, iterations: iterations, converged: !changed }
}

func ownership_region_bit_set(int bits, int bit) bool {
    value := bits / bit
    return value % 2 == 1
}

func ownership_region_union_value(int target_bits, int source_bits) int {
    result := target_bits
    point := 0
    bit := 1
    while point < 31 {
        if ownership_region_bit_set(source_bits, bit) {
            if !ownership_region_bit_set(result, bit) { result = result + bit }
        }
        point = point + 1
        bit = bit * 2
    }
    result
}
