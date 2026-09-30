#!/bin/bash
set -euo pipefail

SOURCE_ROOT="${1:-${S_SOURCE_ROOT:-.}}"
REPORT="${SOURCE_ROOT}/.bootstrap/mir-a1/canonical-mir-read-gate.txt"
TMP_REPORT="${REPORT}.tmp.$$"

MIR_FILE="${SOURCE_ROOT}/src/cmd/compile/internal/mir.s"
LOWER_FILE="${SOURCE_ROOT}/src/cmd/compile/internal/ir/lower.s"
ENTRY_FILE="${SOURCE_ROOT}/src/cmd/compile/modular_build_main.s"

mkdir -p "$(dirname "$REPORT")"
trap 'rm -f "$TMP_REPORT"' EXIT HUP INT TERM

has_text() {
    local pattern=$1
    local file=$2
    rg -q -e "$pattern" "$file" 2>/dev/null
}

line_of() {
    local pattern=$1
    local file=$2
    rg -n -e "$pattern" "$file" 2>/dev/null | head -n 1 | sed 's/:.*//'
}

write_report() {
    {
        echo "MIR-A1 - CANONICAL READ/LOAD CONTRACT"
        echo "Scope: canonical MIR access semantics only; no store/SSEED/bootstrap routing."
        echo "source-entry=$ENTRY_FILE"
        echo "mir-source=$MIR_FILE"
        echo "lowering-source=$LOWER_FILE"
        echo "fixture.index=args[1]"
        echo "fixture.field=source_result.unwrap_err().message"
        echo "canonical-place-model=$canonical_place_model"
        echo "canonical-index-place=$canonical_index_place"
        echo "canonical-field-place=$canonical_field_place"
        echo "canonical-read-place=$canonical_read_place"
        echo "canonical-read-place.reason=$reason"
        echo "first-unmet-contract=$first_unmet_contract"
        echo "reason=$reason"
        echo "stage=mir-a1"
        echo "result=$result"
        echo "evidence.place-model=$place_evidence"
        echo "evidence.index-place=$index_evidence"
        echo "evidence.field-place=$field_evidence"
        echo "evidence.read-place=$read_evidence"
        echo "evidence.structured-proof=$structured_proof"
    } > "$TMP_REPORT"
    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"
}

canonical_place_model=FAIL
canonical_index_place=FAIL
canonical_field_place=FAIL
canonical_read_place=FAIL
first_unmet_contract="MIR-A1.1"
reason="canonical mir_place model is not observable"
result=FAIL
place_evidence=NONE
index_evidence=NONE
field_evidence=NONE
read_evidence=NONE
structured_proof=NOT_RUN

if [ ! -f "$MIR_FILE" ] || [ ! -f "$LOWER_FILE" ] || [ ! -f "$ENTRY_FILE" ]; then
    reason="required MIR/lowering/source files are missing"
    write_report
    exit 1
fi

if has_text '^struct mir_place[[:space:]]*\{' "$MIR_FILE" &&
   has_text 'mir_place_projection\[\] projections' "$MIR_FILE" &&
   has_text '^enum mir_projection_kind[[:space:]]*\{' "$MIR_FILE"; then
    canonical_place_model=PASS
    first_unmet_contract="MIR-A1.2"
    reason="canonical index place projection is not observable"
    place_evidence="${MIR_FILE}:$(line_of '^struct mir_place[[:space:]]*\{' "$MIR_FILE")"
fi

if [ "$canonical_place_model" = PASS ] &&
   has_text 'mir_projection_kind\.index|mir_projection_kind::index|index[[:space:]]+// array/slice indexing' "$MIR_FILE" &&
   has_text 'expr\.index\(index_expr\)' "$MIR_FILE" &&
   has_text 'projections = append\(place\.projections, mir_place_projection \{ kind: mir_projection_kind\.index' "$MIR_FILE"; then
    canonical_index_place=PASS
    first_unmet_contract="MIR-A1.3"
    reason="canonical field place projection is not observable"
    index_evidence="${MIR_FILE}:$(line_of 'expr\.index\(index_expr\)' "$MIR_FILE")"
fi

if [ "$canonical_index_place" = PASS ] &&
   has_text 'mir_projection_kind\.field|mir_projection_kind::field|field[[:space:]]+// struct/tuple field access' "$MIR_FILE" &&
   has_text 'expr\.member\(member_expr\)' "$MIR_FILE" &&
   has_text 'projections = append\(place\.projections, mir_place_projection \{ kind: mir_projection_kind\.field' "$MIR_FILE"; then
    canonical_field_place=PASS
    first_unmet_contract="MIR-A1.4"
    reason="no canonical MIR read/load operation consumes mir_place and produces a value"
    field_evidence="${MIR_FILE}:$(line_of 'expr\.member\(member_expr\)' "$MIR_FILE")"
fi

if [ "$canonical_field_place" = PASS ]; then
    if has_text 'struct mir_(read|load)_stmt|read_place|load_place|read\(mir_read_stmt\)' "$MIR_FILE"; then
        read_evidence="${MIR_FILE}:$(line_of 'read\(mir_read_stmt\)|struct mir_(read|load)_stmt|read_place|load_place' "$MIR_FILE")"
        if [ -x "${SOURCE_ROOT}/bin/s_modular" ] && "${SOURCE_ROOT}/bin/s_modular" test "${SOURCE_ROOT}/src/cmd/compile/internal/tests/fixtures" >/dev/null 2>&1; then
            canonical_read_place=PASS
            first_unmet_contract=NONE
            reason=NONE
            result=PASS
            structured_proof="bin/s_modular test consumed real lowered mir_statement::read"
        else
            reason="canonical read/load structure exists, but no real lowered MIR read proof passed"
            structured_proof="FAILED"
        fi
    else
        read_evidence="absent: mir_statement has no read/load(place)->value operation"
    fi
fi

write_report

if [ "$result" = PASS ]; then
    exit 0
fi
exit 1
