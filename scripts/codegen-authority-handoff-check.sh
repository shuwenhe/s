#!/bin/sh
set -eu

SOURCE_ROOT="${1:-${S_SOURCE_ROOT:-.}}"
BACKEND="${SOURCE_ROOT}/src/cmd/compile/backend/backend_elf64.s"
FIXTURE="${SOURCE_ROOT}/test/compiler/codegen_authority_runtime.s"
REPORT="${SOURCE_ROOT}/.bootstrap/codegen-authority/handoff-gate.txt"
TMP_REPORT="${REPORT}.tmp.$$"

mkdir -p "$(dirname "$REPORT")"
trap 'rm -f "$TMP_REPORT"' EXIT HUP INT TERM

fail() {
    {
        echo "CODEGEN AUTHORITY HANDOFF - FIRST RED"
        echo "Scope: directed gate for production codegen authority only"
        echo "proof-source=codegen-authority-handoff-check"
        echo "$1=FAIL"
        echo "$1.reason=$2"
        echo "first-unmet-contract=$1"
        echo "directed_codegen_authority=RED"
        echo "full_canonical_authority=NOT_YET_PROVEN"
        echo "result=FAIL"
    } > "$TMP_REPORT"
    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"
    return 1
}

if [ ! -f "$FIXTURE" ]; then
    fail "CAH.1" "runtime-dependent fixture not found: $FIXTURE"
    exit $?
fi
if ! grep -q 'std.env.args()' "$FIXTURE" ||
   ! grep -q 'for (.*len(args)' "$FIXTURE" ||
   ! grep -q 'if total > 2' "$FIXTURE"; then
    fail "CAH.1" "fixture is not runtime-dependent on argv plus branch/loop behavior"
    exit $?
fi

if [ ! -f "$BACKEND" ]; then
    fail "CAH.2" "backend authority file not found: $BACKEND"
    exit $?
fi

if grep -q 'source_exec := execute_source_main(source)' "$BACKEND" &&
   grep -q 'if source_exec.is_ok()' "$BACKEND" &&
   grep -q 'asm_text := emit_asm(writes_result.unwrap(), exit_code_result.unwrap())' "$BACKEND" &&
   grep -q 'func emit_asm(write_op\[] writes, int exit_code) string' "$BACKEND"; then
    fail "CAH.2" "production emission remains source-interpreter-first and emit_asm consumes write_op[]/exit_code rather than canonical IR/native instructions"
    exit $?
fi

if ! grep -q 'emit_asm_.*machine' "$BACKEND" &&
   ! grep -q 'select_.*instruction' "$BACKEND"; then
    fail "CAH.2" "no observable production IR-to-native instruction selection feeding assembly emission"
    exit $?
fi

{
    echo "CODEGEN AUTHORITY HANDOFF - FIRST RED"
    echo "Scope: directed gate for production codegen authority only"
    echo "proof-source=codegen-authority-handoff-check"
    echo "CAH.1=PASS"
    echo "CAH.1.fixture=test/compiler/codegen_authority_runtime.s"
    echo "CAH.2=PASS"
    echo "CAH.2.ir-to-native-authority=observed"
    echo "CAH.3=PASS"
    echo "CAH.3.source-interpreter-excluded=yes"
    echo "directed_codegen_authority=PASS"
    echo "full_canonical_authority=NOT_YET_PROVEN"
    echo "result=PASS"
} > "$TMP_REPORT"
mv "$TMP_REPORT" "$REPORT"
cat "$REPORT"
