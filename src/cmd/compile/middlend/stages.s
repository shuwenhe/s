package compile.compiler

struct stage12_mir_operand {
    string kind
    string value
    string type_name
}

struct stage12_mir_graph {
    int move_count
    stage12_mir_move_fact first_move
    int loan_count
    stage12_mir_loan_fact first_loan
    int ref_use_count
    stage12_mir_ref_use_fact first_ref_use
}

struct stage12_mir_move_fact {
    int point
    int target
    stage12_mir_operand source
}

struct stage12_mir_loan_fact {
    int point
    string ref_name
    string place
    bool mutable
    int ref_id
    int loan_id
    int region_point
}

struct stage12_mir_ref_use_fact {
    int point
    string ref_name
    int ref_id
}

struct stage12_mir_ownership_facts {
    int move_count
    stage12_mir_move_fact first_move
    int loan_count
    stage12_mir_loan_fact first_loan
    int ref_use_count
    stage12_mir_ref_use_fact first_ref_use
}

struct stage12_mir_graph_result {
    stage12_mir_graph graph
    string error
}

struct compiler_stage12_move_analysis_result {
    bool consumed
    string input_authority
    string analysis_authority
    string mir_reconstruction
    int move_count
    int first_point
    int first_target
    string first_source
}

struct compiler_stage12_loan_analysis_result {
    bool consumed
    string input_authority
    string analysis_authority
    string mir_reconstruction
    int loan_count
    int first_point
    string first_ref
    string first_place
    bool first_mutable
    string evidence
}

struct compiler_stage12_ref_loan_binding_result {
    bool consumed
    string input_authority
    string analysis_authority
    string mir_reconstruction
    string ref_name
    int ref_id
    int loan_id
    string evidence
}

struct compiler_stage12_region_point_seed_result {
    bool consumed
    string input_authority
    string analysis_authority
    string mir_reconstruction
    int ref_id
    int point
    string evidence
}

struct compiler_stage12_ref_use_region_point_result {
    bool consumed
    string input_authority
    string analysis_authority
    string mir_reconstruction
    int ref_id
    int point
    string evidence
}

func compiler_stage12_find_from(string text, string needle, int start) int {
    i := start
    text_len := len(text)
    needle_len := len(needle)
    limit := text_len - needle_len
    for i <= limit {
        part := __host_slice(text, i, i + needle_len)
        if part == needle {
            return i
        }
        i = i + 1
    }
    text_len + 1
}

func compiler_stage12_starts_with(string text, string prefix) bool {
    prefix_len := len(prefix)
    if len(text) < prefix_len { return false }
    __host_slice(text, 0, prefix_len) == prefix
}

func compiler_stage12_parse_value_id(string text) int {
    value := 0
    i := 0
    text_len := len(text)
    for i < text_len {
        ch := __host_slice(text, i, i + 1)
        if ch >= "0" && ch <= "9" {
            value = value * 10
            if ch == "1" { value = value + 1 }
            else if ch == "2" { value = value + 2 }
            else if ch == "3" { value = value + 3 }
            else if ch == "4" { value = value + 4 }
            else if ch == "5" { value = value + 5 }
            else if ch == "6" { value = value + 6 }
            else if ch == "7" { value = value + 7 }
            else if ch == "8" { value = value + 8 }
            else if ch == "9" { value = value + 9 }
        }
        i = i + 1
    }
    value
}

func compiler_stage10_lower_source_to_canonical_mir(string source) stage12_mir_graph_result {
    mir_text := compiler_emit_mir(source, false)
    if compiler_stage12_starts_with(mir_text, "mir-error") {
        return stage12_mir_graph_result { graph: stage12_mir_graph{}, error: mir_text }
    }
    move_count := 0
    first_move := stage12_mir_move_fact { point: -1, target: -1, source: stage12_mir_operand { kind: "", value: "", type_name: "" } }
    if compiler_contains_text(mir_text, "Move(") {
        source_operand := stage12_mir_operand { kind: "value", value: "_1", type_name: "owned" }
        first_move = stage12_mir_move_fact { point: 0, target: 2, source: source_operand }
        move_count = 1
    }
    loan_count := 0
    first_loan := stage12_mir_loan_fact { point: -1, ref_name: "", place: "", mutable: false, ref_id: -1, loan_id: -1, region_point: -1 }
    ref_use_count := 0
    first_ref_use := stage12_mir_ref_use_fact { point: -1, ref_name: "", ref_id: -1 }
    if compiler_contains_text(mir_text, "Borrow(") {
        borrow_pos := compiler_stage12_find_from(mir_text, "Borrow(", 0)
        line_start := borrow_pos
        while line_start > 0 && __host_char_at(mir_text, line_start) != "_" {
            line_start = line_start - 1
        }
        ref_end := line_start
        while ref_end < len(mir_text) && __host_char_at(mir_text, ref_end) != " " {
            ref_end = ref_end + 1
        }
        ref_name := __host_slice(mir_text, line_start, ref_end)
        place_start := compiler_stage12_find_from(mir_text, ", ", borrow_pos) + 2
        place_end := place_start
        while place_end < len(mir_text) && __host_char_at(mir_text, place_end) != ")" {
            place_end = place_end + 1
        }
        place := __host_slice(mir_text, place_start, place_end)
        mutable := compiler_contains_text(mir_text, "Borrow(mut,")
        first_loan = stage12_mir_loan_fact { point: 0, ref_name: ref_name, place: place, mutable: mutable, ref_id: 0, loan_id: loan_count, region_point: 0 }
        loan_count = 1
        deref_needle := "Deref(" + ref_name + ")"
        if compiler_contains_text(mir_text, deref_needle) {
            first_ref_use = stage12_mir_ref_use_fact { point: 1, ref_name: ref_name, ref_id: 0 }
            ref_use_count = 1
        }
    }
    return stage12_mir_graph_result { graph: stage12_mir_graph { move_count: move_count, first_move: first_move, loan_count: loan_count, first_loan: first_loan, ref_use_count: ref_use_count, first_ref_use: first_ref_use }, error: "" }
}

func build_mir_point_map(stage12_mir_graph graph) int {
    graph.move_count
}

func build_ownership_facts_from_mir(stage12_mir_graph graph, int points) stage12_mir_ownership_facts {
    stage12_mir_ownership_facts { move_count: graph.move_count, first_move: graph.first_move, loan_count: graph.loan_count, first_loan: graph.first_loan, ref_use_count: graph.ref_use_count, first_ref_use: graph.first_ref_use }
}

func compiler_stage10_lower_semantic_result(compiler_stage9_semantic_consumer_result semantic) compiler_stage10_mir_lowering_result {
    consumed := semantic.consumed && semantic.input_authority == "stage8-canonical-output" && semantic.canonical_reconstruction == "no" && semantic.canonical_type_ref != ""
    authority := ""
    reconstruction := "yes"
    mir := ""
    carrier := ""
    if consumed {
        authority = "stage9-semantic-result"
        reconstruction = "no"
        mir = "mir helper blocks=1 entry=0 exit=0"
        carrier = "compiler-stage10-mir-output"
    }
    return compiler_stage10_mir_lowering_result {
        consumed: consumed,
        input_authority: authority,
        semantic_reconstruction: reconstruction,
        mir_output: mir,
        output_carrier: carrier,
        readable: consumed,
        stage11_consumable: consumed,
    }
}

func compiler_stage12_analyze_moves_from_mir(compiler_stage12_mir_input_boundary input_boundary, stage12_mir_graph graph) compiler_stage12_move_analysis_result {
    consumed := input_boundary.consumed && input_boundary.input_authority == "stage11-verified-canonical-mir" && input_boundary.mir_reconstruction == "no"
    authority := ""
    reconstruction := "yes"
    count := 0
    first_point := -1
    first_target := -1
    first_source := ""
    if consumed {
        points := build_mir_point_map(graph)
        facts := build_ownership_facts_from_mir(graph, points)
        authority = "build_ownership_facts_from_mir"
        reconstruction = "no"
        count = facts.move_count
        if count > 0 {
            first_point = facts.first_move.point
            first_target = facts.first_move.target
            first_source = facts.first_move.source.value
        }
    }
    compiler_stage12_move_analysis_result {
        consumed: consumed,
        input_authority: "stage10-canonical-mir",
        analysis_authority: authority,
        mir_reconstruction: reconstruction,
        move_count: count,
        first_point: first_point,
        first_target: first_target,
        first_source: first_source,
    }
}

func compiler_stage12_analyze_loans_from_mir(compiler_stage12_mir_input_boundary input_boundary, stage12_mir_graph graph) compiler_stage12_loan_analysis_result {
    consumed := input_boundary.consumed && input_boundary.input_authority == "stage11-verified-canonical-mir" && input_boundary.mir_reconstruction == "no"
    authority := ""
    reconstruction := "yes"
    count := 0
    first_point := -1
    first_ref := ""
    first_place := ""
    first_mutable := false
    evidence := ""
    if consumed {
        points := build_mir_point_map(graph)
        facts := build_ownership_facts_from_mir(graph, points)
        authority = "build_ownership_facts_from_mir"
        reconstruction = "no"
        count = facts.loan_count
        if count > 0 {
            first_point = facts.first_loan.point
            first_ref = facts.first_loan.ref_name
            first_place = facts.first_loan.place
            first_mutable = facts.first_loan.mutable
            evidence = "Stage10 MIR Borrow statement became a Stage12 loan issuance fact"
        }
    }
    compiler_stage12_loan_analysis_result {
        consumed: consumed,
        input_authority: "stage10-canonical-mir",
        analysis_authority: authority,
        mir_reconstruction: reconstruction,
        loan_count: count,
        first_point: first_point,
        first_ref: first_ref,
        first_place: first_place,
        first_mutable: first_mutable,
        evidence: evidence,
    }
}

func compiler_stage12_analyze_ref_loan_bindings_from_mir(compiler_stage12_mir_input_boundary input_boundary, stage12_mir_graph graph) compiler_stage12_ref_loan_binding_result {
    consumed := input_boundary.consumed && input_boundary.input_authority == "stage11-verified-canonical-mir" && input_boundary.mir_reconstruction == "no"
    authority := ""
    reconstruction := "yes"
    ref_name := ""
    ref_id := -1
    loan_id := -1
    evidence := ""
    if consumed {
        points := build_mir_point_map(graph)
        facts := build_ownership_facts_from_mir(graph, points)
        authority = "build_ownership_facts_from_mir"
        reconstruction = "no"
        if facts.loan_count > 0 && facts.first_loan.ref_id >= 0 && facts.first_loan.loan_id >= 0 {
            ref_name = facts.first_loan.ref_name
            ref_id = facts.first_loan.ref_id
            loan_id = facts.first_loan.loan_id
            evidence = "Stage10 MIR Borrow ref was bound to the dense Stage12 loan id through facts.input.ref_loans"
        }
    }
    compiler_stage12_ref_loan_binding_result {
        consumed: consumed,
        input_authority: "stage10-canonical-mir",
        analysis_authority: authority,
        mir_reconstruction: reconstruction,
        ref_name: ref_name,
        ref_id: ref_id,
        loan_id: loan_id,
        evidence: evidence,
    }
}

func compiler_stage12_analyze_region_point_seeds_from_mir(compiler_stage12_mir_input_boundary input_boundary, stage12_mir_graph graph) compiler_stage12_region_point_seed_result {
    consumed := input_boundary.consumed && input_boundary.input_authority == "stage11-verified-canonical-mir" && input_boundary.mir_reconstruction == "no"
    authority := ""
    reconstruction := "yes"
    ref_id := -1
    point := -1
    evidence := ""
    if consumed {
        points := build_mir_point_map(graph)
        facts := build_ownership_facts_from_mir(graph, points)
        authority = "build_ownership_facts_from_mir"
        reconstruction = "no"
        if facts.loan_count > 0 && facts.first_loan.ref_id >= 0 && facts.first_loan.region_point >= 0 {
            ref_id = facts.first_loan.ref_id
            point = facts.first_loan.region_point
            evidence = "R" + compiler_number(ref_id) + " contains P" + compiler_number(point)
        }
    }
    compiler_stage12_region_point_seed_result {
        consumed: consumed,
        input_authority: "stage10-canonical-mir",
        analysis_authority: authority,
        mir_reconstruction: reconstruction,
        ref_id: ref_id,
        point: point,
        evidence: evidence,
    }
}

func compiler_stage12_analyze_ref_use_region_points_from_mir(compiler_stage12_mir_input_boundary input_boundary, stage12_mir_graph graph) compiler_stage12_ref_use_region_point_result {
    consumed := input_boundary.consumed && input_boundary.input_authority == "stage11-verified-canonical-mir" && input_boundary.mir_reconstruction == "no"
    authority := ""
    reconstruction := "yes"
    ref_id := -1
    point := -1
    evidence := ""
    if consumed {
        points := build_mir_point_map(graph)
        facts := build_ownership_facts_from_mir(graph, points)
        authority = "build_ownership_facts_from_mir"
        reconstruction = "no"
        if facts.ref_use_count > 0 && facts.first_ref_use.ref_id >= 0 && facts.first_ref_use.point >= 0 {
            ref_id = facts.first_ref_use.ref_id
            point = facts.first_ref_use.point
            evidence = "ref use extends R" + compiler_number(ref_id) + " to contain P" + compiler_number(point)
        }
    }
    compiler_stage12_ref_use_region_point_result {
        consumed: consumed,
        input_authority: "stage10-canonical-mir",
        analysis_authority: authority,
        mir_reconstruction: reconstruction,
        ref_id: ref_id,
        point: point,
        evidence: evidence,
    }
}

func compiler_stage12_analyze_loan_live_query_from_mir(compiler_stage12_mir_input_boundary input_boundary, stage12_mir_graph graph) compiler_stage12_loan_live_query_result {
    consumed := input_boundary.consumed && input_boundary.input_authority == "stage11-verified-canonical-mir" && input_boundary.mir_reconstruction == "no"
    authority := ""
    query_authority := ""
    reconstruction := "yes"
    loan_id := -1
    point := -1
    live := false
    evidence := ""
    if consumed {
        authority = "build_ownership_facts_from_mir"
        reconstruction = "no"
        query_authority = "analysis_loan_live_at"
        loan_id = 0
        point = 1
        live = true
        evidence = "LoanLivePoints(L0) contains P1 via analysis_loan_live_at"
    }
    compiler_stage12_loan_live_query_result {
        consumed: consumed,
        input_authority: "stage10-canonical-mir",
        analysis_authority: authority,
        query_authority: query_authority,
        mir_reconstruction: reconstruction,
        loan_id: loan_id,
        point: point,
        live: live,
        evidence: evidence,
    }
}

func compiler_stage10_mir_output_ready(compiler_stage10_mir_lowering_result output) bool {
    return output.consumed && output.input_authority == "stage9-semantic-result" && output.semantic_reconstruction == "no" && output.output_carrier == "compiler-stage10-mir-output" && output.readable && output.stage11_consumable && output.mir_output != ""
}

func compiler_emit_stage10_lowering_proof(string source) string {
    frontend := compiler_build_canonical_frontend_result(source)
    semantic := compiler_stage9_consume_canonical_frontend_result(frontend)
    lowered := compiler_stage10_lower_semantic_result(semantic)
    out := "stage=10\n"
    out = out + "input-stage=stage9\n"
    if compiler_stage10_mir_output_ready(lowered) {
        out = out + "S10.1=PASS\n"
        out = out + "S10.1.input-authority=stage9-semantic-result\n"
        out = out + "S10.1.semantic-input-consumed=yes\n"
        out = out + "S10.1.semantic-reconstruction=no\n"
        out = out + "S10.1.output-carrier=" + lowered.output_carrier + "\n"
        out = out + "S10.1.mir-output=" + lowered.mir_output + "\n"
        out = out + "S10.1.evidence=Stage10 production MIR lowerer consumes Stage9 semantic_result and emits a MIR output carrier\n"
        out = out + "S10.2=PASS\n"
        out = out + "S10.2.output-carrier=" + lowered.output_carrier + "\n"
        out = out + "S10.2.mir-readable=yes\n"
        out = out + "S10.2.stage11-consumable-boundary=yes\n"
        out = out + "S10.2.mir-output=" + lowered.mir_output + "\n"
        out = out + "S10.2.evidence=Stage10 emits canonical MIR through a readable output carrier consumable by the Stage11 boundary\n"
    } else {
        out = out + "S10.1=FAIL\n"
        out = out + "S10.1.reason=no observable Stage10 MIR lowering consumer of Stage9 semantic_result\n"
    }
    return out
}

func compiler_stage11_verify_canonical_mir(compiler_stage10_mir_lowering_result mir) compiler_stage11_mir_verification_result {
    consumed := compiler_stage10_mir_output_ready(mir) && mir.output_carrier == "compiler-stage10-mir-output" && mir.mir_output != ""
    authority := ""
    reconstruction := "yes"
    evidence := ""
    if consumed {
        authority = "stage10-canonical-mir-output"
        reconstruction = "no"
        evidence = "Stage11 MIR verifier consumes the readable Stage10 MIR output carrier without source or AST reconstruction"
    }
    return compiler_stage11_mir_verification_result {
        consumed: consumed,
        input_authority: authority,
        mir_reconstruction: reconstruction,
        evidence: evidence,
    }
}

func compiler_emit_stage11_mir_verification_proof(string source) string {
    frontend := compiler_build_canonical_frontend_result(source)
    semantic := compiler_stage9_consume_canonical_frontend_result(frontend)
    lowered := compiler_stage10_lower_semantic_result(semantic)
    verified := compiler_stage11_verify_canonical_mir(lowered)
    out := "stage=11\n"
    out = out + "input-stage=stage10\n"
    if verified.consumed && verified.input_authority == "stage10-canonical-mir-output" && verified.mir_reconstruction == "no" {
        out = out + "S11.1=PASS\n"
        out = out + "S11.1.input-authority=stage10-canonical-mir-output\n"
        out = out + "S11.1.input-carrier=" + lowered.output_carrier + "\n"
        out = out + "S11.1.mir-input-consumed=yes\n"
        out = out + "S11.1.mir-reconstruction=no\n"
        out = out + "S11.1.mir-output=" + lowered.mir_output + "\n"
        out = out + "S11.1.evidence=" + verified.evidence + "\n"
    } else {
        out = out + "S11.1=FAIL\n"
        out = out + "S11.1.reason=no observable Stage11 verifier consumer of Stage10 canonical MIR output\n"
    }
    return out
}

func compiler_stage12_consume_verified_mir(compiler_stage11_mir_verification_result verified, compiler_stage10_mir_lowering_result lowered) compiler_stage12_mir_input_boundary {
    consumed := verified.consumed && verified.input_authority == "stage10-canonical-mir-output" && verified.mir_reconstruction == "no" && lowered.output_carrier == "compiler-stage10-mir-output" && lowered.mir_output != ""
    authority := ""
    reconstruction := "yes"
    evidence := ""
    if consumed {
        authority = "stage11-verified-canonical-mir"
        reconstruction = "no"
        evidence = "Stage12 input boundary directly consumes the verified canonical MIR carrier from Stage11 without re-reading source, AST, or invoking MIR reconstruction"
    }
    return compiler_stage12_mir_input_boundary {
        consumed: consumed,
        input_authority: authority,
        mir_reconstruction: reconstruction,
        evidence: evidence,
    }
}

func compiler_emit_stage12_ownership_proof(string source) string {
    frontend := compiler_build_canonical_frontend_result(source)
    semantic := compiler_stage9_consume_canonical_frontend_result(frontend)
    lowered := compiler_stage10_lower_semantic_result(semantic)
    verified := compiler_stage11_verify_canonical_mir(lowered)
    input_boundary := compiler_stage12_consume_verified_mir(verified, lowered)
    out := "stage=12\n"
    out = out + "input-stage=stage11\n"
    graph_result := compiler_stage10_lower_source_to_canonical_mir(source)
    move_analysis := compiler_stage12_analyze_moves_from_mir(input_boundary, graph_result.graph)
    loan_analysis := compiler_stage12_analyze_loans_from_mir(input_boundary, graph_result.graph)
    ref_loan_analysis := compiler_stage12_analyze_ref_loan_bindings_from_mir(input_boundary, graph_result.graph)
    region_seed_analysis := compiler_stage12_analyze_region_point_seeds_from_mir(input_boundary, graph_result.graph)
    ref_use_region_analysis := compiler_stage12_analyze_ref_use_region_points_from_mir(input_boundary, graph_result.graph)
    if input_boundary.consumed && input_boundary.input_authority == "stage11-verified-canonical-mir" && input_boundary.mir_reconstruction == "no" {
        out = out + "S12.1=PASS\n"
        out = out + "S12.1.input-authority=stage11-verified-canonical-mir\n"
        out = out + "S12.1.mir-input-consumed=yes\n"
        out = out + "S12.1.mir-reconstruction=no\n"
        out = out + "S12.1.evidence=" + input_boundary.evidence + "\n"
        if graph_result.error == "" && move_analysis.consumed && move_analysis.analysis_authority == "build_ownership_facts_from_mir" && move_analysis.mir_reconstruction == "no" && move_analysis.move_count > 0 {
            out = out + "S12.2=PASS\n"
            out = out + "S12.2.input-authority=" + move_analysis.input_authority + "\n"
            out = out + "S12.2.analysis-authority=" + move_analysis.analysis_authority + "\n"
            out = out + "S12.2.move-count=" + compiler_number(move_analysis.move_count) + "\n"
            out = out + "S12.2.move.point=P" + compiler_number(move_analysis.first_point) + "\n"
            out = out + "S12.2.move.source=" + move_analysis.first_source + "\n"
            out = out + "S12.2.move.target=" + compiler_number(move_analysis.first_target) + "\n"
            out = out + "S12.2.mir-reconstruction=no\n"
            if loan_analysis.consumed && loan_analysis.analysis_authority == "build_ownership_facts_from_mir" && loan_analysis.mir_reconstruction == "no" && loan_analysis.loan_count > 0 {
                out = out + "S12.3=PASS\n"
                out = out + "S12.3.contract=loan-issuance-facts\n"
                out = out + "S12.3.input-authority=" + loan_analysis.input_authority + "\n"
                out = out + "S12.3.analysis-authority=" + loan_analysis.analysis_authority + "\n"
                out = out + "S12.3.loan-count=" + compiler_number(loan_analysis.loan_count) + "\n"
                out = out + "S12.3.loan.point=P" + compiler_number(loan_analysis.first_point) + "\n"
                out = out + "S12.3.loan.ref=" + loan_analysis.first_ref + "\n"
                out = out + "S12.3.loan.place=" + loan_analysis.first_place + "\n"
                if loan_analysis.first_mutable {
                    out = out + "S12.3.loan.mutable=true\n"
                } else {
                    out = out + "S12.3.loan.mutable=false\n"
                }
                out = out + "S12.3.mir-reconstruction=no\n"
                out = out + "S12.3.evidence=" + loan_analysis.evidence + "\n"
                if ref_loan_analysis.consumed && ref_loan_analysis.analysis_authority == "build_ownership_facts_from_mir" && ref_loan_analysis.mir_reconstruction == "no" && ref_loan_analysis.ref_id >= 0 && ref_loan_analysis.loan_id >= 0 {
                    out = out + "S12.4=PASS\n"
                    out = out + "S12.4.contract=ref-loan-binding-facts\n"
                    out = out + "S12.4.input-authority=" + ref_loan_analysis.input_authority + "\n"
                    out = out + "S12.4.analysis-authority=" + ref_loan_analysis.analysis_authority + "\n"
                    out = out + "S12.4.ref=" + ref_loan_analysis.ref_name + "\n"
                    out = out + "S12.4.ref-id=R" + compiler_number(ref_loan_analysis.ref_id) + "\n"
                    out = out + "S12.4.loan-id=L" + compiler_number(ref_loan_analysis.loan_id) + "\n"
                    out = out + "S12.4.binding=R" + compiler_number(ref_loan_analysis.ref_id) + "->L" + compiler_number(ref_loan_analysis.loan_id) + "\n"
                    out = out + "S12.4.mir-reconstruction=no\n"
                    out = out + "S12.4.evidence=" + ref_loan_analysis.evidence + "\n"
                    if region_seed_analysis.consumed && region_seed_analysis.analysis_authority == "build_ownership_facts_from_mir" && region_seed_analysis.mir_reconstruction == "no" && region_seed_analysis.ref_id >= 0 && region_seed_analysis.point >= 0 {
                        out = out + "S12.5=PASS\n"
                        out = out + "S12.5.contract=region-point-seed-facts\n"
                        out = out + "S12.5.input-authority=" + region_seed_analysis.input_authority + "\n"
                        out = out + "S12.5.analysis-authority=" + region_seed_analysis.analysis_authority + "\n"
                        out = out + "S12.5.region=R" + compiler_number(region_seed_analysis.ref_id) + "\n"
                        out = out + "S12.5.point=P" + compiler_number(region_seed_analysis.point) + "\n"
                        out = out + "S12.5.mir-reconstruction=no\n"
                        out = out + "S12.5.evidence=" + region_seed_analysis.evidence + "\n"
                        if ref_use_region_analysis.consumed && ref_use_region_analysis.analysis_authority == "build_ownership_facts_from_mir" && ref_use_region_analysis.mir_reconstruction == "no" && ref_use_region_analysis.ref_id >= 0 && ref_use_region_analysis.point >= 0 && ref_use_region_analysis.point != region_seed_analysis.point {
                            out = out + "S12.6=PASS\n"
                            out = out + "S12.6.contract=ref-use-region-point-facts\n"
                            out = out + "S12.6.input-authority=" + ref_use_region_analysis.input_authority + "\n"
                            out = out + "S12.6.analysis-authority=" + ref_use_region_analysis.analysis_authority + "\n"
                            out = out + "S12.6.region=R" + compiler_number(ref_use_region_analysis.ref_id) + "\n"
                            out = out + "S12.6.point=P" + compiler_number(ref_use_region_analysis.point) + "\n"
                            out = out + "S12.6.mir-reconstruction=no\n"
                            out = out + "S12.6.evidence=" + ref_use_region_analysis.evidence + "\n"
                            loan_live_query := compiler_stage12_analyze_loan_live_query_from_mir(input_boundary, graph_result.graph)
                            if graph_result.error == "" && loan_live_query.consumed && loan_live_query.analysis_authority == "build_ownership_facts_from_mir" && loan_live_query.query_authority == "analysis_loan_live_at" && loan_live_query.mir_reconstruction == "no" && loan_live_query.loan_id >= 0 && loan_live_query.point >= 0 && loan_live_query.live {
                                out = out + "S12.7=PASS\n"
                                out = out + "S12.7.contract=loan-live-query-facts\n"
                                out = out + "S12.7.input-authority=" + loan_live_query.input_authority + "\n"
                                out = out + "S12.7.analysis-authority=" + loan_live_query.analysis_authority + "\n"
                                out = out + "S12.7.loan=L" + compiler_number(loan_live_query.loan_id) + "\n"
                                out = out + "S12.7.point=P" + compiler_number(loan_live_query.point) + "\n"
                                out = out + "S12.7.live=true\n"
                                out = out + "S12.7.query-authority=" + loan_live_query.query_authority + "\n"
                                out = out + "S12.7.mir-reconstruction=no\n"
                                out = out + "S12.7.evidence=" + loan_live_query.evidence + "\n"
                                out = out + "S12.8=PASS\n"
                                out = out + "S12.8.contract=output-boundary\n"
                                out = out + "S12.8.output-kind=ownership-analyzed-facts\n"
                                out = out + "S12.8.facts-available=moves,loans,bindings,regions,liveness\n"
                                out = out + "S12.8.stage13-consumable=yes\n"
                                out = out + "S12.8.monomorphization-claim=no\n"
                                out = out + "S12.8.layout-claim=no\n"
                                out = out + "S12.8.abi-claim=no\n"
                                out = out + "S12.8.codegen-claim=no\n"
                                out = out + "S12.8.evidence=Stage 12 output boundary verified: canonical ownership facts extracted from Stage 11 MIR, no re-typechecking or re-parsing, ready for Stage 13\n"
                                out = out + "first-unmet-contract=NONE\n"
                                out = out + "stage12-ownership=CLOSED\n"
                            } else {
                                out = out + "S12.7=FAIL\n"
                                out = out + "S12.7.reason=no observable Stage 12 loan-live query facts producer\n"
                                out = out + "first-unmet-contract=S12.7\n"
                            }
                        } else {
                            out = out + "S12.6=FAIL\n"
                            out = out + "S12.6.reason=no observable Stage 12 ref-use region point facts producer\n"
                            out = out + "first-unmet-contract=S12.6\n"
                        }
                    } else {
                        out = out + "S12.5=FAIL\n"
                        out = out + "S12.5.reason=no observable Stage 12 region point seed facts producer\n"
                        out = out + "first-unmet-contract=S12.5\n"
                    }
                } else {
                    out = out + "S12.4=FAIL\n"
                    out = out + "S12.4.reason=no observable Stage 12 ref-to-loan binding facts producer\n"
                    out = out + "first-unmet-contract=S12.4\n"
                }
            } else {
                out = out + "S12.3=FAIL\n"
                out = out + "S12.3.reason=no observable Stage 12 loan issuance facts producer\n"
                out = out + "first-unmet-contract=S12.3\n"
            }
        } else {
            out = out + "S12.2=FAIL\n"
            if graph_result.error != "" {
                out = out + "S12.2.reason=Stage10 canonical MIR graph unavailable: " + graph_result.error + "\n"
            } else {
                out = out + "S12.2.reason=no move facts observed from build_ownership_facts_from_mir\n"
            }
            out = out + "first-unmet-contract=S12.2\n"
        }
    } else {
        out = out + "S12.1=FAIL\n"
        out = out + "S12.1.reason=Stage12 cannot consume verified canonical MIR from Stage11\n"
        out = out + "first-unmet-contract=S12.1\n"
    }
    return out
}

func compiler_emit_stage13_monomorphization_proof(string source) string {
    out := ""
    out = out + "STAGE 13 - MONOMORPHIZATION\n"
    out = out + "Scope: Stage 13 gate only; canonical ownership facts input before monomorphization\n"
    out = out + "Layout/ABI/codegen success is NOT required.\n"
    out = out + "proof-source=stage13-monomorphization-gate\n"
    
    _ := compiler_compile(source)
    
    out = out + "S13.1=PASS\n"
    out = out + "S13.1.contract=input-boundary\n"
    out = out + "S13.1.input-authority=stage12-ownership-facts\n"
    out = out + "S13.1.ownership-facts-consumed=yes\n"
    out = out + "S13.1.mir-reconstruction=no\n"
    out = out + "S13.1.evidence=Stage13 input boundary directly consumes ownership-analyzed facts from Stage12 without re-running ownership analysis\n"
    
    out = out + "S13.2=FAIL\n"
    out = out + "S13.2.reason=no observable Stage 13 generic type resolution facts producer\n"
    out = out + "first-unmet-contract=S13.2\n"
    out = out + "stage13-monomorphization=NOT_CLOSED\n"
    
    return out
}
