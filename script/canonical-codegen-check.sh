#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="${1:-${S_SOURCE_ROOT:-.}}"
COMPILER="${SOURCE_ROOT}/bin/s_compiler"
REPORT="${SOURCE_ROOT}/.bootstrap/stage17/canonical-codegen-gate.txt"
TMP_REPORT="${REPORT}.tmp.$$"
TEST_FILE="${SOURCE_ROOT}/test/native-build/program.s"
mkdir -p "$(dirname "$REPORT")"
WORK=$(mktemp -d "${REPORT}.artifacts.XXXXXXXX")
trap 'rm -f "$TMP_REPORT"' EXIT HUP INT TERM

header() {
    echo 'STAGE 17 - INSTRUCTION SELECTION / CODEGEN'
    echo 'scope=P0 Native Linux/amd64'
    echo 'selfhost=NOT_PROVEN'
    echo "compiler=$COMPILER"
    echo 'proof-source=stage17-native-execution-gate'
    echo "evidence-dir=$WORK"
}
fail() {
    {
        header
        echo "$1=FAIL"
        echo "$1.reason=$2"
        echo "first-unmet-contract=$1"
        echo 'stage17-codegen=NOT_CLOSED'
        echo 'result=FAIL'
    } > "$TMP_REPORT"
    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"
    exit 1
}

[[ -x "$COMPILER" ]] || fail S17.1 "compiler not found or not executable: $COMPILER"
[[ -f "$TEST_FILE" ]] || fail S17.1 "native production fixture not found: $TEST_FILE"
for tool in timeout as "${CC:-cc}" readelf objdump; do
    command -v "$tool" >/dev/null 2>&1 || fail S17.2 "required native verification tool not found: $tool"
done

# The ABI runner supplies values after compilation. The emitted object contains
# the source computation; the runner only parses an integer and prints its result.
cat > "$WORK/runner.c" <<'C'
#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
extern int64_t s_native_entry(int64_t);
int main(int argc, char **argv) {
    char *end = NULL;
    if (argc != 2) return 2;
    errno = 0;
    int64_t input = strtoll(argv[1], &end, 10);
    if (errno || !end || *end) return 2;
    printf("%" PRId64 "\n", s_native_entry(input));
    return 0;
}
C
cp "$TEST_FILE" "$WORK/original.s"
sed 's/product + 4/product + 9/' "$TEST_FILE" > "$WORK/changed.s"
sed 's/left \* right/left - right/' "$TEST_FILE" > "$WORK/subtract.s"
cmp -s "$WORK/original.s" "$WORK/changed.s" && fail S17.1 'source variation fixture did not change'
cmp -s "$WORK/original.s" "$WORK/subtract.s" && fail S17.1 'operation variation fixture did not change'

compile_case() {
    local name=$1
    local assembly="$WORK/$name.asm" object="$WORK/$name.o" executable="$WORK/$name"
    # Every output path is fresh; a successful no-op cannot reuse prior output.
    if ! S_TARGET_OS=linux S_TARGET_ARCH=amd64 timeout 30s "$COMPILER" \
        --emit-amd64 "$WORK/$name.s" "$assembly" > "$WORK/$name.compile.log" 2>&1; then
        fail S17.1 "$name native assembly emission failed; see evidence-dir"
    fi
    [[ -s "$assembly" ]] || fail S17.1 "$name compiler did not produce assembly"
    if ! as --64 -o "$object" "$assembly" > "$WORK/$name.assemble.log" 2>&1; then
        fail S17.1 "$name compiler output is not valid AMD64 assembly"
    fi
    readelf -h "$object" > "$WORK/$name.elf-header.txt" || fail S17.1 "$name object inspection failed"
    if ! grep -Eq 'Class:.*ELF64' "$WORK/$name.elf-header.txt" ||
       ! grep -Eq 'Type:.*REL ' "$WORK/$name.elf-header.txt" ||
       ! grep -Eq 'Machine:.*X86-64' "$WORK/$name.elf-header.txt"; then
        fail S17.1 "$name assembly did not produce a Linux AMD64 relocatable object"
    fi
    if ! "${CC:-cc}" -std=c11 -Wall -Wextra -Werror -O2 \
        "$WORK/runner.c" "$object" -o "$executable" > "$WORK/$name.link.log" 2>&1; then
        fail S17.2 "$name native object did not link with the ABI runner"
    fi
    objdump -dr "$object" > "$WORK/$name.disassembly.txt" || fail S17.1 "$name instruction inspection failed"
}
expect() {
    local name=$1 input=$2 wanted=$3 actual
    if ! actual=$(timeout 5s "$WORK/$name" "$input" 2> "$WORK/$name.run.err"); then
        fail S17.2 "$name executable failed for input $input"
    fi
    printf '%s input=%s wanted=%s actual=%s\n' "$name" "$input" "$wanted" "$actual" >> "$WORK/runtime-results.txt"
    [[ "$actual" == "$wanted" ]] || fail S17.2 "$name input $input: expected $wanted, got $actual"
}

compile_case original
expect original 7 25
expect original 2 10
expect original -2 -2
expect original 0 4
compile_case changed
expect changed 7 30
expect changed -2 3
compile_case subtract
expect subtract 7 8
expect subtract -2 -1
if cmp -s "$WORK/original.asm" "$WORK/changed.asm" ||
   cmp -s "$WORK/original.asm" "$WORK/subtract.asm"; then
    fail S17.1 'source changes did not change generated assembly'
fi
if ! grep -q 'imul' "$WORK/original.disassembly.txt" ||
   ! grep -q 'call' "$WORK/original.disassembly.txt" ||
   ! grep -q 'sub' "$WORK/subtract.disassembly.txt"; then
    fail S17.1 'generated objects lack the exercised multiply/call/subtract instructions'
fi
{
    header
    echo 'S17.1=PASS'
    echo 'S17.1.production-mode=function-mir-to-ssa-to-amd64'
    echo 'S17.1.producer=compile.internal.native_program_assembly/emit_function_ssa_amd64'
    echo 'S17.1.input-artifact=function_ssa_program'
    echo 'S17.1.output-artifact=GNU AMD64 assembly'
    echo 'S17.1.assembly-verified=GNU as ELF64 AMD64 relocatable objects'
    echo 'S17.2=PASS'
    echo 'S17.2.behavior=runtime signed inputs and source/operation variations'
    echo 'S17.2.fixed-artifact-rejected=yes'
    echo 'stage17-codegen=CLOSED'
    echo 'result=PASS'
} > "$TMP_REPORT"
mv "$TMP_REPORT" "$REPORT"
cat "$REPORT"
