package compile.internal.bounds

struct bounds_proof {
    bool safe
    int lower_bound
    int upper_bound
    string reason
}

func bounds_prove_constant_index(int index, int length) bounds_proof {
    if length < 0 {
        return bounds_proof { safe: false, lower_bound: 0, upper_bound: length, reason: "invalid-length" }
    }
    if index < 0 {
        return bounds_proof { safe: false, lower_bound: 0, upper_bound: length, reason: "negative-index" }
    }
    if index >= length {
        return bounds_proof { safe: false, lower_bound: 0, upper_bound: length, reason: "index-out-of-range" }
    }
    bounds_proof { safe: true, lower_bound: 0, upper_bound: length, reason: "constant-index" }
}

// Prove the canonical loop: start <= index < limit, index += step.
// The proof is conservative: only positive steps and a known finite limit qualify.
func bounds_prove_loop(int start, int limit, int step, int length) bounds_proof {
    if length < 0 || step <= 0 {
        return bounds_proof { safe: false, lower_bound: start, upper_bound: limit, reason: "unknown-loop-range" }
    }
    if start < 0 {
        return bounds_proof { safe: false, lower_bound: start, upper_bound: limit, reason: "negative-loop-start" }
    }
    if limit < start || limit > length {
        return bounds_proof { safe: false, lower_bound: start, upper_bound: limit, reason: "loop-limit-not-in-bounds" }
    }
    bounds_proof { safe: true, lower_bound: start, upper_bound: limit, reason: "canonical-loop" }
}

func bounds_should_eliminate(bounds_proof proof) bool {
    proof.safe
}
