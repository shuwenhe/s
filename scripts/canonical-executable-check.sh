#!/bin/sh
set -eu

SOURCE_ROOT="${1:-${S_SOURCE_ROOT:-.}}"
COMPILER="${SOURCE_ROOT}/bin/s_compiler"
DRIVER="${SOURCE_ROOT}/bin/s"
REPORT="${SOURCE_ROOT}/.bootstrap/stage22/canonical-executable-gate.txt"
TMP_REPORT="${REPORT}.tmp.$$"
BACKEND="${SOURCE_ROOT}/src/cmd/compile/backend/backend_elf64.s"
PIPELINE_MAIN="${SOURCE_ROOT}/src/cmd/compile/main.s"
TEST_FILE="${SOURCE_ROOT}/test/simple_test.s"
WORK_DIR="${SOURCE_ROOT}/.bootstrap/stage22/run.$$"

mkdir -p "$(dirname "$REPORT")" "$WORK_DIR"
trap 'rm -rf "$WORK_DIR"; rm -f "$TMP_REPORT"' EXIT HUP INT TERM

fail() {
    {
        echo "STAGE 22 - EXECUTABLE"
        echo "Scope: Stage 22 gate; compiler build output is an executable artifact"
        echo "compiler=$COMPILER"
        echo "proof-source=stage22-executable-gate"
        echo "$1=FAIL"
        echo "$1.reason=$2"
        echo "first-unmet-contract=$1"
        echo "stage22-executable=NOT_CLOSED"
        echo "result=FAIL"
    } > "$TMP_REPORT"
    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"
    return 1
}

if [ ! -x "$COMPILER" ]; then
    fail "S22.1" "compiler not found or not executable: $COMPILER"
    exit $?
fi
if [ ! -x "$DRIVER" ]; then
    fail "S22.1" "build driver not found or not executable: $DRIVER"
    exit $?
fi
if [ ! -f "$BACKEND" ] || [ ! -f "$PIPELINE_MAIN" ]; then
    fail "S22.1" "executable authority files not found"
    exit $?
fi
if [ ! -f "$TEST_FILE" ]; then
    fail "S22.3" "test input file not found: $TEST_FILE"
    exit $?
fi

if ! grep -q 'func build(string path, string output, string ssa_margin_override, bool nostdlib) int' "$BACKEND" ||
   ! grep -q 'ld_argv = append(ld_argv, output)' "$BACKEND" ||
   ! grep -q 'dbg_path := output + ".dbg"' "$BACKEND" ||
   ! grep -q 'stackmap_path := output + ".stackmap"' "$BACKEND"; then
    fail "S22.1" "production build path does not expose final executable and side artifacts"
    exit $?
fi

if ! grep -q 'if command == "build"' "$PIPELINE_MAIN" ||
   ! grep -q 'compile.internal.backend_elf64.build(args\[2\], args\[4\], "", false)' "$PIPELINE_MAIN"; then
    fail "S22.2" "pipeline build command is not wired to backend executable build"
    exit $?
fi

OUT="${WORK_DIR}/stage22.out"
if ! "$DRIVER" build "$TEST_FILE" -o "$OUT" >/dev/null 2>&1; then
    fail "S22.3" "compiler failed to build executable fixture"
    exit $?
fi
if [ ! -f "$OUT" ] || [ ! -s "$OUT" ]; then
    fail "S22.3" "compiler did not write a non-empty executable artifact"
    exit $?
fi
if [ ! -x "$OUT" ]; then
    fail "S22.3" "compiler output is not executable"
    exit $?
fi
{
    echo "STAGE 22 - EXECUTABLE"
    echo "Scope: Stage 22 gate; compiler build output is an executable artifact"
    echo "compiler=$COMPILER"
    echo "proof-source=stage22-executable-gate"
    echo "S22.1=PASS"
    echo "S22.1.production-producer=compile.internal.backend_elf64.build"
    echo "S22.1.output-artifact=executable"
    echo "S22.2=PASS"
    echo "S22.2.command=compile.pipeline.main build"
    echo "S22.2.backend=compile.internal.backend_elf64.build"
    echo "S22.3=PASS"
    echo "S22.3.driver=bin/s"
    echo "S22.3.fixture=test/simple_test.s"
    echo "S22.3.executable=yes"
    echo "stage22-executable=CLOSED"
    echo "result=PASS"
} > "$TMP_REPORT"
mv "$TMP_REPORT" "$REPORT"
cat "$REPORT"
