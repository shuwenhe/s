#!/bin/sh
set -eu

SOURCE_ROOT="${1:-${S_SOURCE_ROOT:-.}}"
COMPILER="${SOURCE_ROOT}/bin/s_compiler"
DRIVER="${SOURCE_ROOT}/bin/s"
REPORT="${SOURCE_ROOT}/.bootstrap/stage22/canonical-executable-gate.txt"
TMP_REPORT="${REPORT}.tmp.$$"
TEST_FILE="${SOURCE_ROOT}/test/native-build/program.s"
WORK_DIR="${SOURCE_ROOT}/.bootstrap/stage22/run.$$"
mkdir -p "$(dirname "$REPORT")" "$WORK_DIR"
trap 'rm -rf "$WORK_DIR"; rm -f "$TMP_REPORT"' EXIT HUP INT TERM

fail() {
    {
        echo 'STAGE 22 - NATIVE EXECUTABLE'
        echo "compiler=$COMPILER"
        echo 'proof-source=stage22-native-runtime-gate'
        echo "$1=FAIL"
        echo "$1.reason=$2"
        echo "first-unmet-contract=$1"
        echo 'stage22-executable=NOT_CLOSED'
        echo 'result=FAIL'
    } > "$TMP_REPORT"
    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"
    exit 1
}

[ -x "$COMPILER" ] && [ -x "$DRIVER" ] || fail S22.1 'native compiler or driver is missing'
[ -f "$TEST_FILE" ] || fail S22.1 'native fixture is missing'
OUT="$WORK_DIR/program"
# A failed Native build is a failure. No legacy or interpreter fallback.
if ! timeout 30s "$DRIVER" build "$TEST_FILE" -o "$OUT" > "$WORK_DIR/build.log" 2>&1; then
    fail S22.2 'production Native build failed'
fi
[ -s "$OUT" ] && [ -x "$OUT" ] || fail S22.3 'no executable artifact'
readelf -h "$OUT" > "$WORK_DIR/elf.txt" || fail S22.3 'output is not ELF'
grep -q 'Advanced Micro Devices X86-64' "$WORK_DIR/elf.txt" || fail S22.3 'output is not amd64'
readelf -l "$OUT" > "$WORK_DIR/segments.txt" || fail S22.3 'cannot inspect ELF segments'
if grep -q INTERP "$WORK_DIR/segments.txt"; then fail S22.3 'unexpected interpreter dependency'; fi
nm "$OUT" > "$WORK_DIR/symbols.txt" || fail S22.3 'cannot inspect native symbols'
if grep -Eq 'seed_compile|runtime_execute|execute_source_main|execute_mir_graph' "$WORK_DIR/symbols.txt"; then
    fail S22.3 'compiler or interpreter symbols in generated program'
fi
sha256sum "$OUT" > "$WORK_DIR/before.sha256"
first=0
second=0
timeout 5s "$OUT" 7 > "$WORK_DIR/first.out" 2>&1 || first=$?
timeout 5s "$OUT" 2 > "$WORK_DIR/second.out" 2>&1 || second=$?
[ "$first" -eq 25 ] && [ "$second" -eq 10 ] || fail S22.4 'same executable does not compute runtime inputs'
sha256sum "$OUT" > "$WORK_DIR/after.sha256"
cmp -s "$WORK_DIR/before.sha256" "$WORK_DIR/after.sha256" || fail S22.4 'executable changed between runs'
{
    echo 'STAGE 22 - NATIVE EXECUTABLE'
    echo "compiler=$COMPILER"
    echo 'proof-source=stage22-native-runtime-gate'
    echo 'S22.1=PASS'
    echo 'S22.1.production-producer=compile.internal.core.native_build'
    echo 'S22.2=PASS'
    echo 'S22.2.pipeline=function-mir-to-function-ssa-to-amd64'
    echo 'S22.2.legacy-fallback=no'
    echo 'S22.3=PASS'
    echo 'S22.3.output-artifact=static-amd64-ELF'
    echo 'S22.3.interpreter-dependency=no'
    echo 'S22.4=PASS'
    echo 'S22.4.runtime-input-7-exit=25'
    echo 'S22.4.runtime-input-2-exit=10'
    echo 'S22.4.same-artifact=yes'
    echo 'stage22-executable=CLOSED'
    echo 'result=PASS'
} > "$TMP_REPORT"
mv "$TMP_REPORT" "$REPORT"
cat "$REPORT"
