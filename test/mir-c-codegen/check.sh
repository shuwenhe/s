#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d /tmp/s-mir-c-codegen.XXXXXX)
printf 'MIR C Codegen artifacts=%s\n' "$work"
cd "$root"
make seed-compiler-bin
git rev-parse HEAD > "$work/commit.txt"
sha256sum src/cmd/compile/internal/mir/program.s src/cmd/compile/internal/codegen/c_program.s \
    src/cmd/compile/seed/runtime/runtime.c test/mir-c-codegen/generate.s \
    bin/s_seed > "$work/input-hashes.txt"
"${CC:-cc}" --version > "$work/host-cc.txt"
sources=(src/cmd/compile/internal/mir/program.s src/cmd/compile/internal/codegen/c_program.s test/mir-c-codegen/generate.s)
timeout 30s ./bin/s_seed --compile-unit "$work/emitter.ir" "${sources[@]}"
S_SOURCE_ROOT="$root" timeout 60s ./bin/s_seed --emit-bin "$work/emitter.ir" "$work/emitter"
expect() {
    local mode=$1 input=$2 wanted=$3
    mkdir -p "$work/$mode"
    timeout 10s "$work/emitter" "$mode" > "$work/$mode/program.c"
    "${CC:-cc}" -std=c11 -Wall -Wextra -Werror -O2 -I"$work/$mode" \
        test/mir-c-codegen/runner.c -o "$work/$mode/native"
    local actual
    actual=$(timeout 10s "$work/$mode/native" "$input")
    if [[ "$actual" != "$wanted" ]]; then
        printf '%s input=%s: wanted %s, got %s\n' "$mode" "$input" "$wanted" "$actual" >&2
        exit 1
    fi
}
expect base 7 25
expect base -2 -2
expect changed 7 30
expect subtract 7 17
expect copy 7 25
expect min 0 -9223372036854775808
expect divide 7 -2
expect divide -7 2
expect modulo 7 1
expect modulo -7 -1
expect wrap 9223372036854775807 -9223372036854775808
expect wrap -9223372036854775808 -9223372036854775807
mkdir -p "$work/divide_zero"
timeout 10s "$work/emitter" divide_zero > "$work/divide_zero/program.c"
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -O2 -I"$work/divide_zero" \
    test/mir-c-codegen/runner.c -o "$work/divide_zero/native"
divide_status=0
timeout 10s "$work/divide_zero/native" 1 > "$work/divide_zero/output" || divide_status=$?
test "$divide_status" -eq 86
test ! -s "$work/divide_zero/output"
mkdir -p "$work/void"
timeout 10s "$work/emitter" void > "$work/void/program.c"
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -O2 -I"$work/void" \
    test/mir-c-codegen/void_runner.c -o "$work/void/native"
timeout 10s "$work/void/native"
for mode in invalid_op undefined external bad_type mutated_ir cfg unknown_after_lowering multiple_results; do
    if timeout 10s "$work/emitter" "$mode" > "$work/$mode.c" 2> "$work/$mode.log"; then
        printf '%s unexpectedly accepted\n' "$mode" >&2
        exit 1
    fi
    test ! -s "$work/$mode.c"
    test -s "$work/$mode.log"
done
timeout 30s ./bin/s_seed --compile-unit "$work/record.ir" test/mir-c-codegen/record_transfer.s
S_SOURCE_ROOT="$root" timeout 60s ./bin/s_seed --emit-bin "$work/record.ir" "$work/record-test"
timeout 10s "$work/record-test"
printf 'MIR -> S C emitter -> host CC -> native execution: PASS\n'
printf 'Runtime input, changed IR, cross-function calls and rejection cases: PASS\n'
