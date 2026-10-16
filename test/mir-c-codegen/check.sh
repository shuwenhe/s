#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d /tmp/s-mir-c-codegen.XXXXXX)
printf 'MIR C Codegen artifacts=%s\n' "$work"
cd "$root"
sources=(src/cmd/compile/internal/mir/program.s)
if test -f src/cmd/compile/internal/codegen/c_program.s; then
    sources+=(src/cmd/compile/internal/codegen/c_program.s)
fi
sources+=(test/mir-c-codegen/generate.s)
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
expect min 0 -9223372036854775808
for mode in invalid_op undefined external bad_type; do
    if timeout 10s "$work/emitter" "$mode" > "$work/$mode.c" 2> "$work/$mode.log"; then
        printf '%s unexpectedly accepted\n' "$mode" >&2
        exit 1
    fi
    test ! -s "$work/$mode.c"
    test -s "$work/$mode.log"
done
printf 'MIR -> S C emitter -> host CC -> native execution: PASS\n'
printf 'Runtime input, changed IR, cross-function calls and rejection cases: PASS\n'
