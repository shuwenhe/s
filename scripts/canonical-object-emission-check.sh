#!/bin/sh
set -eu

SOURCE_ROOT="${1:-${S_SOURCE_ROOT:-.}}"
COMPILER="${SOURCE_ROOT}/bin/s_compiler"
REPORT="${SOURCE_ROOT}/.bootstrap/stage20/canonical-object-emission-gate.txt"
TMP_REPORT="${REPORT}.tmp.$$"
BACKEND="${SOURCE_ROOT}/src/cmd/compile/backend/backend_elf64.s"
OBJECT_CONTRACT="${SOURCE_ROOT}/src/cmd/compile/backend/tools/link/internal/ld/object_contract.s"
ELF_GEN="${SOURCE_ROOT}/src/cmd/compile/backend/backend/elf64_gen.s"

mkdir -p "$(dirname "$REPORT")"
trap 'rm -f "$TMP_REPORT"' EXIT HUP INT TERM

fail() {
    {
        echo "STAGE 20 - OBJECT/ELF EMISSION"
        echo "Scope: Stage 20 gate only; object artifact emission before linking"
        echo "Link/executable success is not required."
        echo "compiler=$COMPILER"
        echo "proof-source=stage20-object-emission-gate"
        echo "$1=FAIL"
        echo "$1.reason=$2"
        echo "first-unmet-contract=$1"
        echo "stage20-object-emission=NOT_CLOSED"
        echo "result=FAIL"
    } > "$TMP_REPORT"
    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"
    return 1
}

if [ ! -x "$COMPILER" ]; then
    fail "S20.1" "compiler not found or not executable: $COMPILER"
    exit $?
fi
if [ ! -f "$BACKEND" ] || [ ! -f "$OBJECT_CONTRACT" ] || [ ! -f "$ELF_GEN" ]; then
    fail "S20.1" "object emission authority files not found"
    exit $?
fi

if ! grep -q 'func build_object(string path, string output, string ssa_margin_override) int' "$BACKEND" ||
   ! grep -q 'asm_path := temp_dir + "/out.s"' "$BACKEND" ||
   ! grep -q 'as_argv = append(as_argv, "as")' "$BACKEND" ||
   ! grep -q 'as_argv = append(as_argv, "-o")' "$BACKEND" ||
   ! grep -q 'as_argv = append(as_argv, output)' "$BACKEND" ||
   ! grep -q 'as_result := std.process.run_process(as_argv)' "$BACKEND"; then
    fail "S20.1" "production build_object path does not expose assembler object emission"
    exit $?
fi

if ! grep -q 'const s_obj_elf = 1' "$OBJECT_CONTRACT" ||
   ! grep -q 'struct s_object' "$OBJECT_CONTRACT" ||
   ! grep -q 'func s_elf_write_rel_header' "$OBJECT_CONTRACT" ||
   ! grep -q 's_obj_put_u16(header, 18, machine)' "$OBJECT_CONTRACT" ||
   ! grep -q 'data\[0\] == 0x7f && data\[1\] == 69 && data\[2\] == 76 && data\[3\] == 70' "$OBJECT_CONTRACT"; then
    fail "S20.2" "ELF object contract does not expose required object facts"
    exit $?
fi

if ! grep -q 'func make_elf64_writer() elf64_writer' "$ELF_GEN" ||
   ! grep -q 'func (elf64_writer\* w) generate_elf() string' "$ELF_GEN" ||
   ! grep -q 'header = header + "\\x7fELF"' "$ELF_GEN"; then
    fail "S20.3" "ELF writer does not expose required file identity facts"
    exit $?
fi

{
    echo "STAGE 20 - OBJECT/ELF EMISSION"
    echo "Scope: Stage 20 gate only; object artifact emission before linking"
    echo "Link/executable success is not required."
    echo "compiler=$COMPILER"
    echo "proof-source=stage20-object-emission-gate"
    echo "S20.1=PASS"
    echo "S20.1.production-producer=compile.internal.backend_elf64.build_object"
    echo "S20.1.tool=as"
    echo "S20.1.output-artifact=object-file"
    echo "S20.2=PASS"
    echo "S20.2.object-contract=src.cmd.link.internal.ld.object_contract"
    echo "S20.2.format=ELF"
    echo "S20.2.machine-field=e_machine"
    echo "S20.3=PASS"
    echo "S20.3.elf-writer=backend.elf64_writer"
    echo "S20.3.magic=0x7f454c46"
    echo "stage20-object-emission=CLOSED"
    echo "result=PASS"
} > "$TMP_REPORT"
mv "$TMP_REPORT" "$REPORT"
cat "$REPORT"
