#!/bin/sh
set -eu

SOURCE_ROOT="${1:-${S_SOURCE_ROOT:-.}}"
COMPILER="${SOURCE_ROOT}/bin/s_compiler"
REPORT="${SOURCE_ROOT}/.bootstrap/stage15/canonical-layout-gate.txt"
RAW_STAGE15="${REPORT}.stage15.raw.$$"
TMP_REPORT="${REPORT}.tmp.$$"
ABIUTILS="${SOURCE_ROOT}/src/cmd/compile/backend/internal/abi/abiutils.s"

mkdir -p "$(dirname "$REPORT")"
trap 'rm -f "$RAW_STAGE15" "$TMP_REPORT"' EXIT HUP INT TERM

proof_value() {
    local key=$1
    local file=$2
    sed -n "s/^${key}=//p" "$file" | tail -n 1
}

fail() {
    {
        echo "STAGE 15 - LAYOUT"
        echo "Scope: Stage 15 gate only; canonical optimized input before ABI/codegen"
        echo "ABI/codegen success is NOT required."
        echo "compiler=$COMPILER"
        echo "proof-source=stage15-layout-gate"
        echo "$1=FAIL"
        echo "$1.reason=$2"
        echo "first-unmet-contract=$1"
        echo "stage15-layout=NOT_CLOSED"
        echo "result=FAIL"
    } > "$TMP_REPORT"
    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"
    return 1
}

if [ ! -x "$COMPILER" ]; then
    fail "S15.1" "compiler not found or not executable: $COMPILER"
    exit $?
fi
if [ ! -f "$ABIUTILS" ]; then
    fail "S15.2" "layout authority file not found: $ABIUTILS"
    exit $?
fi
if ! grep -q 'func type_size(string type_name) int' "$ABIUTILS" ||
   ! grep -q 'func alignment_for_type(string type_name) int' "$ABIUTILS" ||
   ! grep -q 'func append_param_offsets(int\[] offsets, int at, string type_name) offset_result' "$ABIUTILS" ||
   ! grep -q 'func abi_analyze_types(abi_config config, string\[] params, string\[] results) abi_param_result_info' "$ABIUTILS" ||
   ! grep -q 'type_name == "int"' "$ABIUTILS" ||
   ! grep -q 'return 8' "$ABIUTILS" ||
   ! grep -q 'offsets = append(offsets, at)' "$ABIUTILS"; then
    fail "S15.2" "production layout authority does not expose required size/alignment/offset facts"
    exit $?
fi

TEST_FILE="${SOURCE_ROOT}/test/compiler/stage12_move_semantics_real.s"
RAW_STAGE15_TMP="${RAW_STAGE15}.tmp"
"$COMPILER" canonical-layout-proof "$TEST_FILE" "$RAW_STAGE15_TMP" 2>/dev/null || true
mv "$RAW_STAGE15_TMP" "$RAW_STAGE15"

if [ "$(proof_value S15.1 "$RAW_STAGE15")" = "PASS" ] &&
   [ "$(proof_value S15.1.input-authority "$RAW_STAGE15")" = "stage14-optimized-artifact" ] &&
   [ "$(proof_value S15.1.stage14-output-consumed "$RAW_STAGE15")" = "yes" ] &&
   [ "$(proof_value S15.1.reconstruction "$RAW_STAGE15")" = "no" ] &&
   [ "$(proof_value S15.2 "$RAW_STAGE15")" = "PASS" ] &&
   [ -n "$(proof_value S15.2.producer "$RAW_STAGE15")" ] &&
   [ -n "$(proof_value S15.2.data-structure "$RAW_STAGE15")" ] &&
   [ -n "$(proof_value S15.2.consumer "$RAW_STAGE15")" ] &&
   [ "$(proof_value S15.2.fact.size "$RAW_STAGE15")" = "8" ] &&
   [ "$(proof_value S15.2.fact.align "$RAW_STAGE15")" = "8" ] &&
   [ "$(proof_value S15.2.fact.offset0 "$RAW_STAGE15")" = "0" ] &&
   [ "$(proof_value stage15-layout "$RAW_STAGE15")" = "CLOSED" ]; then
    {
        echo "STAGE 15 - LAYOUT"
        echo "Scope: Stage 15 gate only; canonical optimized input before ABI/codegen"
        echo "ABI/codegen success is NOT required."
        echo "compiler=$COMPILER"
        echo "proof-source=stage15-layout-gate"
        cat "$RAW_STAGE15" | sed -n '/^S15\./p'
        echo "stage15-layout=CLOSED"
        echo "result=PASS"
    } > "$TMP_REPORT"
    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"
    exit 0
fi

fail "S15.1" "no observable Stage 15 proof producer"
exit $?
