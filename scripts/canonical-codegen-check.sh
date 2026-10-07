#!/bin/sh
set -eu

SOURCE_ROOT="${1:-${S_SOURCE_ROOT:-.}}"
COMPILER="${SOURCE_ROOT}/bin/s_compiler"
REPORT="${SOURCE_ROOT}/.bootstrap/stage17/canonical-codegen-gate.txt"
RAW_STAGE17="${REPORT}.stage17.raw.$$"
TMP_REPORT="${REPORT}.tmp.$$"
BACKEND="${SOURCE_ROOT}/src/cmd/compile/backend/backend_elf64.s"
INSTR_SELECT="${SOURCE_ROOT}/src/cmd/compile/backend/backend/instr_select.s"
INSTRUCTION_SELECTOR="${SOURCE_ROOT}/src/cmd/compile/backend/backend/instruction_selector.s"
SSA_LOWER="${SOURCE_ROOT}/src/cmd/compile/backend/backend/ssa_lower.s"

mkdir -p "$(dirname "$REPORT")"
trap 'rm -f "$RAW_STAGE17" "$TMP_REPORT"' EXIT HUP INT TERM

proof_value() {
    local key=$1
    local file=$2
    sed -n "s/^${key}=//p" "$file" | tail -n 1
}

fail() {
    {
        echo "STAGE 17 - INSTRUCTION SELECTION / CODEGEN"
        echo "Scope: Stage 17 gate only; production fused codegen before register allocation/machine code"
        echo "Register allocation/object/link success is NOT required."
        echo "compiler=$COMPILER"
        echo "proof-source=stage17-codegen-gate"
        echo "$1=FAIL"
        echo "$1.reason=$2"
        echo "first-unmet-contract=$1"
        echo "stage17-codegen=NOT_CLOSED"
        echo "result=FAIL"
    } > "$TMP_REPORT"
    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"
    return 1
}

if [ ! -x "$COMPILER" ]; then
    fail "S17.1" "compiler not found or not executable: $COMPILER"
    exit $?
fi
if [ ! -f "$BACKEND" ] || [ ! -f "$INSTR_SELECT" ] || [ ! -f "$INSTRUCTION_SELECTOR" ] || [ ! -f "$SSA_LOWER" ]; then
    fail "S17.2" "codegen authority files not found"
    exit $?
fi

if ! grep -q 'writes_result := compile_writes(parsed, graph)' "$BACKEND" ||
   ! grep -q 'exit_code_result := compile_exit_code(parsed, graph)' "$BACKEND" ||
   ! grep -q 'asm_text := emit_asm(writes_result.unwrap(), exit_code_result.unwrap())' "$BACKEND" ||
   ! grep -q 'func emit_asm(write_op\[] writes, int exit_code) string' "$BACKEND" ||
   ! grep -q 'return emit_asm_amd64(writes, exit_code' "$BACKEND" ||
   ! grep -q 'func emit_asm_amd64(write_op\[] writes, int exit_code) string' "$BACKEND" ||
   ! grep -q 'text_lines = append(text_lines, "    mov \$1, %rax")' "$BACKEND" ||
   ! grep -q 'text_lines = append(text_lines, "    mov \$" + std.prelude.to_string(op.fd) + ", %rdi")' "$BACKEND" ||
   ! grep -q 'text_lines = append(text_lines, "    syscall")' "$BACKEND" ||
   ! grep -q 'text_lines = append(text_lines, "    mov \$" + std.prelude.to_string(exit_code) + ", %eax")' "$BACKEND"; then
    fail "S17.1" "production fused codegen/emission authority does not expose required amd64 facts"
    exit $?
fi

if ! grep -q 'func (is\* instr_selector) select_add_i64' "$INSTR_SELECT" ||
   ! grep -q 'func new_instruction_selector() instruction_selector' "$INSTRUCTION_SELECTOR" ||
   ! grep -q 'func (m\* ssa_to_machine) lower_value(int value_id)' "$SSA_LOWER"; then
    fail "S17.2" "side selector modules are not observable"
    exit $?
fi

if grep -q 'make_instr_selector' "$BACKEND" ||
   grep -q 'new_instruction_selector' "$BACKEND" ||
   grep -q 'make_ssa_to_machine' "$BACKEND" ||
   grep -q 'select_add_instruction' "$BACKEND" ||
   grep -q 'select_add_i64' "$BACKEND"; then
    fail "S17.2" "side selector appears wired into production backend_elf64 path"
    exit $?
fi

TEST_FILE="${SOURCE_ROOT}/test/compiler/stage12_move_semantics_real.s"
RAW_STAGE17_TMP="${RAW_STAGE17}.tmp"
"$COMPILER" canonical-codegen-proof "$TEST_FILE" "$RAW_STAGE17_TMP" 2>/dev/null || true
mv "$RAW_STAGE17_TMP" "$RAW_STAGE17"

if [ "$(proof_value S17.1 "$RAW_STAGE17")" = "PASS" ] &&
   [ "$(proof_value S17.1.production-mode "$RAW_STAGE17")" = "fused-codegen-emission" ] &&
   [ "$(proof_value S17.1.producer "$RAW_STAGE17")" = "compile.internal.backend_elf64.compile_writes/compile_exit_code" ] &&
   [ "$(proof_value S17.1.input-artifact "$RAW_STAGE17")" = "write_op[]+exit_code" ] &&
   [ "$(proof_value S17.1.arch-dispatch "$RAW_STAGE17")" = "compile.internal.backend_elf64.emit_asm" ] &&
   [ "$(proof_value S17.1.amd64-authority "$RAW_STAGE17")" = "compile.internal.backend_elf64.emit_asm_amd64" ] &&
   [ "$(proof_value S17.1.ssa-program-direct-input "$RAW_STAGE17")" = "no" ] &&
   [ "$(proof_value S17.1.machine-ir-artifact "$RAW_STAGE17")" = "none" ] &&
   [ "$(proof_value S17.1.reconstruction "$RAW_STAGE17")" = "no" ] &&
   [ "$(proof_value S17.1.fact.arch "$RAW_STAGE17")" = "amd64" ] &&
   [ "$(proof_value S17.1.fact.emitted-op "$RAW_STAGE17")" = "syscall" ] &&
   [ "$(proof_value S17.1.fact.register "$RAW_STAGE17")" = "%rax" ] &&
   [ "$(proof_value S17.1.fact.exit-register "$RAW_STAGE17")" = "%eax" ] &&
   [ "$(proof_value S17.2 "$RAW_STAGE17")" = "PASS" ] &&
   [ "$(proof_value S17.2.side-selector-present "$RAW_STAGE17")" = "yes" ] &&
   [ "$(proof_value S17.2.side-selector-production-wired "$RAW_STAGE17")" = "no" ] &&
   [ "$(proof_value S17.2.side-selector-authoritative "$RAW_STAGE17")" = "no" ] &&
   [ "$(proof_value stage17-codegen "$RAW_STAGE17")" = "CLOSED" ]; then
    {
        echo "STAGE 17 - INSTRUCTION SELECTION / CODEGEN"
        echo "Scope: Stage 17 gate only; production fused codegen before register allocation/machine code"
        echo "Register allocation/object/link success is NOT required."
        echo "compiler=$COMPILER"
        echo "proof-source=stage17-codegen-gate"
        sed -n '/^S17\./p' "$RAW_STAGE17"
        echo "stage17-codegen=CLOSED"
        echo "result=PASS"
    } > "$TMP_REPORT"
    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"
    exit 0
fi

fail "S17.1" "no observable Stage 17 fused codegen proof producer"
exit $?
