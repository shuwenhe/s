#!/bin/sh
set -eu

SOURCE_ROOT="${1:-${S_SOURCE_ROOT:-.}}"
COMPILER="${SOURCE_ROOT}/bin/s_compiler"
REPORT="${SOURCE_ROOT}/.bootstrap/stage19/canonical-machine-code-gate.txt"
TMP_REPORT="${REPORT}.tmp.$$"
BACKEND="${SOURCE_ROOT}/src/cmd/compile/backend/backend_elf64.s"
MACHINE_BUILDER="${SOURCE_ROOT}/src/cmd/compile/backend/backend/codegen_x86_64.s"
NATIVE_COMPILER="${SOURCE_ROOT}/src/cmd/compile/backend/backend/native_compiler.s"

mkdir -p "$(dirname "$REPORT")"
trap 'rm -f "$TMP_REPORT"' EXIT HUP INT TERM

fail() {
    {
        echo "STAGE 19 - MACHINE CODE"
        echo "Scope: Stage 19 gate only; machine instruction bytes before object emission"
        echo "Object/link/executable success is not required."
        echo "compiler=$COMPILER"
        echo "proof-source=stage19-machine-code-gate"
        echo "$1=FAIL"
        echo "$1.reason=$2"
        echo "first-unmet-contract=$1"
        echo "stage19-machine-code=NOT_CLOSED"
        echo "result=FAIL"
    } > "$TMP_REPORT"
    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"
    return 1
}

if [ ! -x "$COMPILER" ]; then
    fail "S19.1" "compiler not found or not executable: $COMPILER"
    exit $?
fi
if [ ! -f "$BACKEND" ] || [ ! -f "$MACHINE_BUILDER" ] || [ ! -f "$NATIVE_COMPILER" ]; then
    fail "S19.1" "machine code authority files not found"
    exit $?
fi

if ! grep -q 'func emit_asm(write_op\[] writes, int exit_code) string' "$BACKEND" ||
   ! grep -q 'func emit_asm_amd64(write_op\[] writes, int exit_code) string' "$BACKEND" ||
   ! grep -q 'text_lines = append(text_lines, "    mov \$1, %rax")' "$BACKEND" ||
   ! grep -q 'text_lines = append(text_lines, "    syscall")' "$BACKEND" ||
   ! grep -q 'text_lines = append(text_lines, "    mov \$" + std.prelude.to_string(exit_code) + ", %eax")' "$BACKEND"; then
    fail "S19.1" "production backend does not expose amd64 machine-instruction emission facts"
    exit $?
fi

if ! grep -q 'struct machine_code_builder' "$MACHINE_BUILDER" ||
   ! grep -q 'machine_code: int\[]' "$MACHINE_BUILDER" ||
   ! grep -q 'func (machine_code_builder\* b) emit_byte(int value)' "$MACHINE_BUILDER" ||
   ! grep -q 'func (machine_code_builder\* b) emit_mov_immediate_to_register' "$MACHINE_BUILDER" ||
   ! grep -q 'func (machine_code_builder\* b) get_machine_code() int\[]' "$MACHINE_BUILDER" ||
   ! grep -q 'b.emit_byte(184 + (reg_id & 7))' "$MACHINE_BUILDER"; then
    fail "S19.2" "machine byte builder does not expose required instruction encoding facts"
    exit $?
fi

if ! grep -q 'func (native_compiler\* nc) get_machine_code() int\[]' "$NATIVE_COMPILER" ||
   ! grep -q 'nc.builder.get_machine_code()' "$NATIVE_COMPILER"; then
    fail "S19.3" "native compiler does not expose machine code artifact access"
    exit $?
fi

{
    echo "STAGE 19 - MACHINE CODE"
    echo "Scope: Stage 19 gate only; machine instruction bytes before object emission"
    echo "Object/link/executable success is not required."
    echo "compiler=$COMPILER"
    echo "proof-source=stage19-machine-code-gate"
    echo "S19.1=PASS"
    echo "S19.1.production-producer=compile.internal.backend_elf64.emit_asm_amd64"
    echo "S19.1.production-artifact=assembly-text"
    echo "S19.1.fact.opcode=syscall"
    echo "S19.1.fact.register=%rax"
    echo "S19.1.fact.exit-register=%eax"
    echo "S19.2=PASS"
    echo "S19.2.byte-builder=backend.machine_code_builder"
    echo "S19.2.byte-artifact=int[]"
    echo "S19.2.encoding-fact=mov-imm64"
    echo "S19.3=PASS"
    echo "S19.3.consumer=backend.native_compiler.get_machine_code"
    echo "stage19-machine-code=CLOSED"
    echo "result=PASS"
} > "$TMP_REPORT"
mv "$TMP_REPORT" "$REPORT"
cat "$REPORT"
