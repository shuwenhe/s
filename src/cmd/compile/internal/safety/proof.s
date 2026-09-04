package compile.internal.safety

use compile.internal.semantic.check_detailed
use compile.internal.semantic.semantic_error

struct safety_proof {
    bool proven
    int diagnostic_count
    int type_errors
    int ownership_errors
    int borrow_errors
    int lifetime_errors
    int unsafe_errors
    string summary
}

func classify_safety_error(semantic_error diagnostic, safety_proof* proof) () {
    code := diagnostic.code
    if code == "e3055" || code == "e3056" || code == "e3057" || code == "e3058" {
        proof.borrow_errors = proof.borrow_errors + 1
    } else if code == "e3052" || code == "e3053" {
        proof.lifetime_errors = proof.lifetime_errors + 1
    } else if code == "e3059" || code == "e3066" || code == "e3067" {
        proof.ownership_errors = proof.ownership_errors + 1
    } else if code == "e3060" || code == "e3061" {
        proof.unsafe_errors = proof.unsafe_errors + 1
    } else {
        proof.type_errors = proof.type_errors + 1
    }
}

func prove_safety(string source) safety_proof {
    diagnostics := check_detailed(source)
    proof := safety_proof {
        proven: len(diagnostics) == 0,
        diagnostic_count: len(diagnostics),
        type_errors: 0,
        ownership_errors: 0,
        borrow_errors: 0,
        lifetime_errors: 0,
        unsafe_errors: 0,
        summary: "",
    }
    i := 0
    for i < len(diagnostics) {
        classify_safety_error(diagnostics[i], &proof)
        i = i + 1
    }
    proof.summary = "safety-proof type=" + (proof.type_errors as string)
        + " ownership=" + (proof.ownership_errors as string)
        + " borrow=" + (proof.borrow_errors as string)
        + " lifetime=" + (proof.lifetime_errors as string)
        + " unsafe=" + (proof.unsafe_errors as string)
        + " diagnostics=" + (proof.diagnostic_count as string)
    proof
}

func safety_proof_report(safety_proof proof) string {
    status := "rejected"
    if proof.proven {
        status = "proven"
    }
    status + " " + proof.summary
}
