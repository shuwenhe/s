#!/bin/sh
set -eu

SOURCE_ROOT="${1:-${S_SOURCE_ROOT:-.}}"
COMPILER="${SOURCE_ROOT}/bin/s_compiler"
REPORT="${SOURCE_ROOT}/.bootstrap/stage16/canonical-abi-gate.txt"
RAW_STAGE16="${REPORT}.stage16.raw.$$"
TMP_REPORT="${REPORT}.tmp.$$"
BACKEND="${SOURCE_ROOT}/src/cmd/compile/backend/backend_elf64.s"
ABIUTILS="${SOURCE_ROOT}/src/cmd/compile/backend/internal/abi/abiutils.s"

mkdir -p "$(dirname "$REPORT")"
trap 'rm -f "$RAW_STAGE16" "$TMP_REPORT"' EXIT HUP INT TERM

proof_value() {
    local key=$1
    local file=$2
    sed -n "s/^${key}=//p" "$file" | tail -n 1
}

fail() {
    {
        echo "STAGE 16 - ABI"
        echo "Scope: Stage 16 gate only; canonical layout input before codegen"
        echo "Codegen/object/link success is NOT required."
        echo "compiler=$COMPILER"
        echo "proof-source=stage16-abi-gate"
        echo "$1=FAIL"
        echo "$1.reason=$2"
        echo "first-unmet-contract=$1"
        echo "stage16-abi=NOT_CLOSED"
        echo "result=FAIL"
    } > "$TMP_REPORT"
    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"
    return 1
}

if [ ! -x "$COMPILER" ]; then
    fail "S16.1" "compiler not found or not executable: $COMPILER"
    exit $?
fi
if [ ! -f "$BACKEND" ] || [ ! -f "$ABIUTILS" ]; then
    fail "S16.2" "ABI authority files not found"
    exit $?
fi
if ! grep -q 'func build_abi_emit_plan(string arch, source_file source) string' "$BACKEND" ||
   ! grep -q 'func collect_abi_behavior(string arch, source_file source) abi_behavior_entry\[]' "$BACKEND" ||
   ! grep -q 'func abi_param_location(string arch, int index) string' "$BACKEND" ||
   ! grep -q 'func abi_emit_ret_plan(string arch, string ret_type, int ret_parts, int aggregate_size) string' "$BACKEND" ||
   ! grep -q 'func validate_ssa_abi_contracts(string arch, string ssa_text)' "$BACKEND" ||
   ! grep -q 'func validate_abi_coverage(string arch)' "$BACKEND" ||
   ! grep -q 'abi_payload := build_abi_behavior_artifact' "$BACKEND" ||
   ! grep -q 'abi_emit_payload := build_abi_emit_plan' "$BACKEND" ||
   ! grep -q 'if index == 0 { return "%rdi" }' "$BACKEND" ||
   ! grep -q 'return "stack+" + std.prelude.to_string((index - abi_variadic_gp_limit(arch)) \* 8)' "$BACKEND" ||
   ! grep -q 'func abi_analyze_types(abi_config config, string\[] params, string\[] results) abi_param_result_info' "$ABIUTILS"; then
    fail "S16.2" "production ABI authority does not expose required classification/artifact/consumer facts"
    exit $?
fi

TEST_FILE="${SOURCE_ROOT}/test/compiler/stage12_move_semantics_real.s"
RAW_STAGE16_TMP="${RAW_STAGE16}.tmp"
"$COMPILER" canonical-abi-proof "$TEST_FILE" "$RAW_STAGE16_TMP" 2>/dev/null || true
mv "$RAW_STAGE16_TMP" "$RAW_STAGE16"

if [ "$(proof_value S16.1 "$RAW_STAGE16")" = "PASS" ] &&
   [ "$(proof_value S16.1.input-authority "$RAW_STAGE16")" = "stage15-layout-artifact" ] &&
   [ "$(proof_value S16.1.stage15-output-consumed "$RAW_STAGE16")" = "yes" ] &&
   [ "$(proof_value S16.1.reconstruction "$RAW_STAGE16")" = "no" ] &&
   [ "$(proof_value S16.2 "$RAW_STAGE16")" = "PASS" ] &&
   [ -n "$(proof_value S16.2.producer "$RAW_STAGE16")" ] &&
   [ -n "$(proof_value S16.2.data-structure "$RAW_STAGE16")" ] &&
   [ -n "$(proof_value S16.2.artifact "$RAW_STAGE16")" ] &&
   [ -n "$(proof_value S16.2.consumer "$RAW_STAGE16")" ] &&
   [ "$(proof_value S16.2.fact.arch "$RAW_STAGE16")" = "amd64" ] &&
   [ "$(proof_value S16.2.fact.param0 "$RAW_STAGE16")" = "%rdi" ] &&
   [ "$(proof_value S16.2.fact.param6 "$RAW_STAGE16")" = "stack+0" ] &&
   [ "$(proof_value S16.2.fact.return "$RAW_STAGE16")" = "%rax" ] &&
   [ "$(proof_value S16.2.fact.stack-align "$RAW_STAGE16")" = "16" ] &&
   [ "$(proof_value stage16-abi "$RAW_STAGE16")" = "CLOSED" ]; then
    {
        echo "STAGE 16 - ABI"
        echo "Scope: Stage 16 gate only; canonical layout input before codegen"
        echo "Codegen/object/link success is NOT required."
        echo "compiler=$COMPILER"
        echo "proof-source=stage16-abi-gate"
        sed -n '/^S16\./p' "$RAW_STAGE16"
        echo "stage16-abi=CLOSED"
        echo "result=PASS"
    } > "$TMP_REPORT"
    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"
    exit 0
fi

fail "S16.1" "no observable Stage 16 proof producer"
exit $?
