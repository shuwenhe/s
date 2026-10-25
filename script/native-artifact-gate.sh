#!/usr/bin/env bash
# Behavioral checks for the production P0 native artifact boundaries.
set -euo pipefail
export LC_ALL=C
stage=${1:?usage: native-artifact-gate.sh STAGE SOURCE_ROOT}
root=$(cd "${2:-${S_SOURCE_ROOT:-.}}" && pwd)
case "$stage" in
    19) title='MACHINE CODE'; name=machine-code ;;
    20) title='OBJECT/ELF EMISSION'; name=object-emission ;;
    21) title=LINKING; name=linking ;;
    *) echo "unsupported artifact stage: $stage" >&2; exit 2 ;;
esac
compiler="$root/bin/s_compiler"
source="$root/test/native-build/program.s"
directory="$root/.bootstrap/stage$stage"
mkdir -p "$directory"
report="$directory/canonical-$name-gate.txt"
temporary="$report.tmp.$$"
work=$(mktemp -d "$directory/native.XXXXXXXX")
trap 'rm -f "$temporary"' EXIT

header() {
    echo "STAGE $stage - $title"
    echo 'scope=P0 Native Linux/amd64'
    echo 'selfhost=NOT_PROVEN'
    echo "compiler=$compiler"
    echo "proof-source=stage$stage-native-artifact-gate"
    echo "evidence-dir=$work"
}
fail() {
    {
        header
        echo "S$stage.$1=FAIL"
        echo "S$stage.$1.reason=$2"
        echo "first-unmet-contract=S$stage.$1"
        echo "stage$stage-$name=NOT_CLOSED"
        echo 'result=FAIL'
    } > "$temporary"
    mv "$temporary" "$report"
    cat "$report"
    exit 1
}

[[ -x "$compiler" ]] || fail 1 'native compiler is missing'
[[ -f "$source" ]] || fail 1 'native source fixture is missing'

if [[ "$stage" == 21 ]]; then
    binary="$work/program"
    timeout 30s "$compiler" build "$source" -o "$binary" > "$work/build.log" 2>&1 || fail 1 'production native build failed'
    [[ -s "$binary" && -x "$binary" ]] || fail 1 'no executable artifact'
    readelf -h "$binary" > "$work/header.txt" || fail 2 'output is not ELF'
    grep -Eq 'Type:.*EXEC' "$work/header.txt" || fail 2 'output is not an executable ELF'
    grep -Eq 'Machine:.*X86-64' "$work/header.txt" || fail 2 'output is not amd64'
    readelf -l "$binary" > "$work/segments.txt" || fail 2 'cannot inspect load segments'
    if grep -q INTERP "$work/segments.txt"; then fail 2 'unexpected dynamic interpreter'; fi
    nm -u "$binary" > "$work/undefined.txt" || fail 2 'cannot inspect unresolved symbols'
    [[ ! -s "$work/undefined.txt" ]] || fail 2 'unresolved symbols remain after linking'
    nm "$binary" > "$work/symbols.txt" || fail 2 'cannot inspect linked symbols'
    grep -q 's_native_entry' "$work/symbols.txt" || fail 2 'native entry point is missing'
    if grep -Eq 'seed_compile|runtime_execute|execute_source_main|execute_mir_graph' "$work/symbols.txt"; then
        fail 2 'compiler or interpreter linked into output'
    fi
    for pair in '7 25' '2 10' '-2 254'; do
        read -r input expected <<< "$pair"
        actual=0
        timeout 5s "$binary" "$input" > "$work/run-$input.log" 2>&1 || actual=$?
        [[ "$actual" -eq "$expected" ]] || fail 3 "linked program: input $input returned $actual, expected $expected"
    done
else
    object="$work/program.o"
    timeout 30s "$compiler" --emit-native-object "$source" "$object" > "$work/build.log" 2>&1 || fail 1 'production native object emission failed'
    [[ -s "$object" ]] || fail 1 'no object artifact'
    readelf -h "$object" > "$work/header.txt" || fail 2 'output is not ELF'
    grep -Eq 'Class:.*ELF64' "$work/header.txt" || fail 2 'output is not ELF64'
    grep -Eq 'Type:.*REL' "$work/header.txt" || fail 2 'output is not relocatable'
    grep -Eq 'Machine:.*X86-64' "$work/header.txt" || fail 2 'output is not amd64'
    if [[ "$stage" == 19 ]]; then
        objdump -dr "$object" > "$work/disassembly.txt" || fail 2 'cannot decode machine instructions'
        grep -Eq '[[:space:]]call' "$work/disassembly.txt" || fail 2 'direct call instruction is missing'
        grep -Eq '[[:space:]]imul' "$work/disassembly.txt" || fail 2 'integer multiplication instruction is missing'
    else
        readelf -Ws "$object" > "$work/symbols.txt" || fail 2 'cannot inspect object symbols'
        grep -q 's_native_entry' "$work/symbols.txt" || fail 2 'native entry symbol is missing'
        readelf -r "$object" > "$work/relocations.txt" || fail 2 'cannot inspect relocations'
        grep -Eq 'R_X86_64_(PLT32|PC32).*s_native_fn_' "$work/relocations.txt" || fail 2 'native call relocation is missing'
    fi
    # Link the exact emitted object to an independent ABI consumer. The expected
    # values are hand-derived from input * 3 + 4, including a negative input.
    cat > "$work/runner.c" <<'C'
#include <stdint.h>
extern int64_t s_native_entry(int64_t);
int main(void) {
    return s_native_entry(7) == 25 && s_native_entry(2) == 10 &&
           s_native_entry(-2) == -2 ? 0 : 1;
}
C
    "${CC:-cc}" -std=c11 -Wall -Wextra -Werror "$work/runner.c" "$object" -o "$work/runner" > "$work/link.log" 2>&1 || fail 3 'native object failed to link with ABI consumer'
    timeout 5s "$work/runner" > "$work/run.log" 2>&1 || fail 3 'emitted object does not compute runtime inputs'
fi

{
    header
    echo "S$stage.1=PASS"
    echo "S$stage.2=PASS"
    echo "S$stage.3=PASS"
    if [[ "$stage" == 21 ]]; then
        echo "S$stage.production-producer=compile.internal.native_install_assembly + GNU ld"
        echo "S$stage.output-artifact=static-amd64-ELF"
    else
        echo "S$stage.production-producer=compile.internal.emit_function_ssa_amd64 + GNU as"
        echo "S$stage.output-artifact=amd64-ELF-relocatable-object"
    fi
    if [[ "$stage" == 21 ]]; then
        echo "S$stage.runtime-exit-statuses=7:25,2:10,-2:254"
    else
        echo "S$stage.runtime-results=7:25,2:10,-2:-2"
    fi
    echo "stage$stage-$name=CLOSED"
    echo 'result=PASS'
} > "$temporary"
mv "$temporary" "$report"
cat "$report"
