#!/bin/bash
set -euo pipefail

SOURCE_ROOT="${1:-${S_SOURCE_ROOT:-.}}"
REPORT="${SOURCE_ROOT}/.bootstrap/l2.4/canonical-sseed-read-place-gate.txt"
TMP_REPORT="${REPORT}.tmp.$$"
RAW_MIR_A1="${REPORT}.mir-a1.raw.$$"
READ_IR="${REPORT}.read-index.ir.$$"
READ_BIN="${REPORT}.read-index.bin.$$"
READ_RUN="${REPORT}.read-index.run.$$"

MIR_GATE="${SOURCE_ROOT}/scripts/canonical-mir-read-check.sh"
SEED_IR="${SOURCE_ROOT}/src/cmd/compile/seed/intermediate/ir.h"
SEED_GENERATOR="${SOURCE_ROOT}/src/cmd/compile/seed/code/generator.c"
SEED_NATIVE="${SOURCE_ROOT}/src/cmd/compile/seed/code/native_backend.c"
SEED_STANDALONE="${SOURCE_ROOT}/src/cmd/compile/seed/code/standalone_amd64_backend.c"
SEED_RUNTIME="${SOURCE_ROOT}/src/cmd/compile/seed/runtime/runtime.c"
SEED_BIN="${SOURCE_ROOT}/bin/s_seed"

mkdir -p "$(dirname "$REPORT")"
trap 'rm -f "$TMP_REPORT" "$RAW_MIR_A1" "$READ_IR" "$READ_BIN" "$READ_RUN"' EXIT HUP INT TERM

proof_value() {
    local key=$1
    local file=$2
    sed -n "s/^${key}=//p" "$file" 2>/dev/null | tail -n 1
}

has_text() {
    local pattern=$1
    shift
    rg -q -e "$pattern" "$@" 2>/dev/null
}

write_report() {
    {
        echo "L2.4 - SSEED READ-PLACE CONTRACT"
        echo "Scope: SSEED READ/index consumer only; no field/deref/store/bootstrap routing."
        echo "mir-gate=$MIR_GATE"
        echo "bootstrap-ir-format=SSEED-TARGET-V1"
        echo "fixture=mir_statement::read(place=args[index(1)], result=command)"
        echo "canonical-read-input=$canonical_read_input"
        echo "canonical-index-projection=$canonical_index_projection"
        echo "sseed-read-place-contract=$sseed_read_place_contract"
        echo "sseed-read-index-consumer=$sseed_read_index_consumer"
        echo "sseed-read-place-contract.reason=$reason"
        echo "existing-seed-equivalent=$existing_seed_equivalent"
        echo "forbidden-split-read-semantics=$forbidden_split_read_semantics"
        echo "first-unmet-contract=$first_unmet_contract"
        echo "reason=$reason"
        echo "result=$result"
        echo "evidence.canonical-read=$canonical_read_evidence"
        echo "evidence.sseed-contract=$sseed_contract_evidence"
        echo "evidence.read-index-consumer=$sseed_read_index_evidence"
    } > "$TMP_REPORT"
    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"
}

canonical_read_input=FAIL
canonical_index_projection=FAIL
sseed_read_place_contract=FAIL
sseed_read_index_consumer=FAIL
existing_seed_equivalent=NONE
forbidden_split_read_semantics=NONE
first_unmet_contract=L2.4.1
reason="canonical MIR read(place) gate is not closed"
result=FAIL
canonical_read_evidence=NONE
sseed_contract_evidence=NONE
sseed_read_index_evidence=NONE

if [ ! -x "$MIR_GATE" ]; then
    reason="canonical MIR read gate is missing"
    write_report
    exit 1
fi

if "$MIR_GATE" "$SOURCE_ROOT" >"$RAW_MIR_A1" 2>&1; then
    if [ "$(proof_value canonical-read-place "$RAW_MIR_A1")" = PASS ] &&
       [ "$(proof_value evidence.structured-proof "$RAW_MIR_A1")" = "bin/s_modular test consumed real lowered mir_statement::read" ]; then
        canonical_read_input=PASS
        canonical_read_evidence="$(proof_value evidence.read-place "$RAW_MIR_A1")"
    fi
    if [ "$(proof_value canonical-index-place "$RAW_MIR_A1")" = PASS ]; then
        canonical_index_projection=PASS
    fi
fi

if [ "$canonical_read_input" != PASS ]; then
    write_report
    exit 1
fi

if [ "$canonical_index_projection" != PASS ]; then
    first_unmet_contract=L2.4.2
    reason="canonical index projection is not closed"
    write_report
    exit 1
fi

first_unmet_contract=L2.4.3
reason="no SSEED representation for canonical MIR read(place)->result"

if has_text 'IR_READ|READ_PLACE|READ\|' "$SEED_IR" "$SEED_GENERATOR"; then
    sseed_read_place_contract=PASS
    sseed_contract_evidence="SSEED READ(result, root, projections) representation found"
    first_unmet_contract=L2.4.4
    reason="seed AOT consumer does not execute READ with index projection"
else
    sseed_contract_evidence="absent: SSEED-TARGET-V1 has no unified READ(result, root, projections) representation"
fi

if [ "$sseed_read_place_contract" = PASS ]; then
    cat >"$READ_IR" <<'IR'
SSEED-TARGET-V1
FUNC_BEGIN|main|_|_
MOV|args|[19,42]|_
READ|command|args|index(1)
RET|command|_|_
FUNC_END|main|_|_
IR
    if [ -x "$SEED_BIN" ] && S_SOURCE_ROOT="$SOURCE_ROOT" "$SEED_BIN" --emit-aot "$READ_IR" "$READ_BIN" >"$READ_RUN" 2>&1; then
        set +e
        "$READ_BIN" >>"$READ_RUN" 2>&1
        read_status=$?
        set -e
        if [ "$read_status" -eq 42 ]; then
            sseed_read_index_consumer=PASS
            sseed_read_index_evidence="SSEED READ|command|args|index(1) executed root[index] and returned 42"
            first_unmet_contract=L2.4.5
            reason="READ field projection consumer is not implemented"
        else
            sseed_read_index_evidence="READ/index binary exited $read_status, expected 42"
        fi
    else
        sseed_read_index_evidence="seed AOT failed for READ|command|args|index(1)"
    fi
fi

if has_text '__index_get|INDEX_GET|FIELD_GET|DEREF_GET' "$SEED_IR" "$SEED_GENERATOR" "$SEED_NATIVE" "$SEED_STANDALONE" "$SEED_RUNTIME"; then
    forbidden_split_read_semantics=PRESENT_NON_CANONICAL
    existing_seed_equivalent="legacy/split index helper present, not canonical read(place)"
fi

write_report

if [ "$result" = PASS ]; then
    exit 0
fi
exit 1
