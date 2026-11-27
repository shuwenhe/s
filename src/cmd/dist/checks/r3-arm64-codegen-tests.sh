#!/usr/bin/env bash
set -euo pipefail

root=$(cd "${S_SOURCE_ROOT:-$(dirname "$0")/../../../..}" && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/s-r3-arm64-codegen.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

compiler=${S_R3_COMPILER:-"$root/bin/s_compiler"}

if [ "$(uname -m)" != "aarch64" ]; then
    echo "R3 arm64 codegen tests require native aarch64 host" >&2
    exit 2
fi

if [ ! -x "$compiler" ]; then
    echo "R3 arm64 codegen tests require compiler binary: $compiler" >&2
    exit 2
fi

compile_and_emit() {
    local name=$1
    local src=$2
    local ir="$tmp/$name.ir"
    local bin="$tmp/$name.bin"
    S_TARGET_OS=linux S_TARGET_ARCH=arm64 "$compiler" --compile-unit "$ir" "$src"
    S_TARGET_OS=linux S_TARGET_ARCH=arm64 "$compiler" --emit-bin "$ir" "$bin"
    printf '%s|%s\n' "$ir" "$bin"
}

assert_elf() {
    local bin=$1
    readelf -h "$bin" | grep -q 'Class:.*ELF64'
    readelf -h "$bin" | grep -q 'Machine:.*AArch64'
}

assert_run_exit() {
    local bin=$1
    local arg=$2
    local expected=$3
    set +e
    "$bin" "$arg" >/dev/null 2>&1
    local status=$?
    set -e
    if [ "$status" -ne "$expected" ]; then
        echo "unexpected exit: $bin arg=$arg got=$status want=$expected" >&2
        exit 1
    fi
}

cat > "$tmp/int_call_branch.s" <<'EOF'
package main

func twice(int x) int {
    return x + x
}

func main(int input) int {
    if input < 10 {
        return twice(input) + 1
    }
    return twice(input) + 2
}
EOF

cat > "$tmp/bitwise_shift.s" <<'EOF'
package main

func main(int input) int {
    v := (input << 1) ^ 3
    if v > 20 {
        return v - 5
    }
    return v + 4
}
EOF

pair1=$(compile_and_emit int_call_branch "$tmp/int_call_branch.s")
bin1=${pair1##*|}
assert_elf "$bin1"
assert_run_exit "$bin1" 7 15
assert_run_exit "$bin1" 12 26

pair2=$(compile_and_emit bitwise_shift "$tmp/bitwise_shift.s")
bin2=${pair2##*|}
assert_elf "$bin2"
assert_run_exit "$bin2" 3 5
assert_run_exit "$bin2" 11 16

echo "R3 arm64 codegen integer/control-flow checks passed."
