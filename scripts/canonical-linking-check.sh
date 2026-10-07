#!/bin/sh
set -eu

SOURCE_ROOT="${1:-${S_SOURCE_ROOT:-.}}"
COMPILER="${SOURCE_ROOT}/bin/s_compiler"
REPORT="${SOURCE_ROOT}/.bootstrap/stage21/canonical-linking-gate.txt"
TMP_REPORT="${REPORT}.tmp.$$"
BACKEND="${SOURCE_ROOT}/src/cmd/compile/backend/backend_elf64.s"
LINKER="${SOURCE_ROOT}/src/cmd/compile/backend/tools/link/internal/ld/production_linker.s"
OBJECT_CONTRACT="${SOURCE_ROOT}/src/cmd/compile/backend/tools/link/internal/ld/object_contract.s"

mkdir -p "$(dirname "$REPORT")"
trap 'rm -f "$TMP_REPORT"' EXIT HUP INT TERM

fail() {
    {
        echo "STAGE 21 - LINKING"
        echo "Scope: Stage 21 gate only; object input linked to an output path"
        echo "Executable runtime success is not required."
        echo "compiler=$COMPILER"
        echo "proof-source=stage21-linking-gate"
        echo "$1=FAIL"
        echo "$1.reason=$2"
        echo "first-unmet-contract=$1"
        echo "stage21-linking=NOT_CLOSED"
        echo "result=FAIL"
    } > "$TMP_REPORT"
    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"
    return 1
}

if [ ! -x "$COMPILER" ]; then
    fail "S21.1" "compiler not found or not executable: $COMPILER"
    exit $?
fi
if [ ! -f "$BACKEND" ] || [ ! -f "$LINKER" ] || [ ! -f "$OBJECT_CONTRACT" ]; then
    fail "S21.1" "linking authority files not found"
    exit $?
fi

if ! grep -q 'obj_path := temp_dir + "/out.o"' "$BACKEND" ||
   ! grep -q 'ld_argv := string\[]()' "$BACKEND" ||
   ! grep -q 'ld_argv = append(ld_argv, "ld")' "$BACKEND" ||
   ! grep -q 'ld_argv = append(ld_argv, "-o")' "$BACKEND" ||
   ! grep -q 'ld_argv = append(ld_argv, output)' "$BACKEND" ||
   ! grep -q 'ld_argv = append(ld_argv, obj_path)' "$BACKEND" ||
   ! grep -q 'ld_result := std.process.run_process(ld_argv)' "$BACKEND"; then
    fail "S21.1" "production build path does not expose linker invocation"
    exit $?
fi

if ! grep -q 'func new_production_linker(config linker_config) production_linker' "$LINKER" ||
   ! grep -q 'func (production_linker\* pl) load_object_file(string filename) error' "$LINKER" ||
   ! grep -q 'func (pl\* production_linker) link() error' "$LINKER" ||
   ! grep -q 'func (pl\* production_linker) merge_symbols() error' "$LINKER" ||
   ! grep -q 'func (pl\* production_linker) process_relocations() error' "$LINKER" ||
   ! grep -q 'func (pl\* production_linker) generate_output() error' "$LINKER"; then
    fail "S21.2" "production linker does not expose load/link/output phases"
    exit $?
fi

if ! grep -q 'func s_obj_merge_into(s_object\* obj, s_obj_symbol candidate) int' "$OBJECT_CONTRACT" ||
   ! grep -q 'func s_obj_add_reloc(s_object\* obj, s_obj_reloc reloc) ()' "$OBJECT_CONTRACT" ||
   ! grep -q 'func s_obj_got_entry(s_link_layout\* layout, int symbol) int' "$OBJECT_CONTRACT" ||
   ! grep -q 'func s_obj_plt_entry(s_link_layout\* layout, int symbol) int' "$OBJECT_CONTRACT"; then
    fail "S21.3" "object contract does not expose symbol/relocation link facts"
    exit $?
fi

{
    echo "STAGE 21 - LINKING"
    echo "Scope: Stage 21 gate only; object input linked to an output path"
    echo "Executable runtime success is not required."
    echo "compiler=$COMPILER"
    echo "proof-source=stage21-linking-gate"
    echo "S21.1=PASS"
    echo "S21.1.production-tool=ld"
    echo "S21.1.input-artifact=object-file"
    echo "S21.1.output-path=compiler-output"
    echo "S21.2=PASS"
    echo "S21.2.linker=src.cmd.link.internal.ld.production_linker"
    echo "S21.2.phases=load_object_file,merge_symbols,process_relocations,generate_output"
    echo "S21.3=PASS"
    echo "S21.3.symbol-contract=s_obj_merge_into"
    echo "S21.3.relocation-contract=s_obj_add_reloc"
    echo "stage21-linking=CLOSED"
    echo "result=PASS"
} > "$TMP_REPORT"
mv "$TMP_REPORT" "$REPORT"
cat "$REPORT"
