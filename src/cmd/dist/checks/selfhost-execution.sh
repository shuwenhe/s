#!/usr/bin/env bash
# Exercise the compiler's source -> native artifact -> executable boundary.
set -euo pipefail
compiler=${1:?usage: selfhost-execution.sh COMPILER OUTPUT_DIR}
work=${2:?usage: selfhost-execution.sh COMPILER OUTPUT_DIR}
root=$(cd "${S_SOURCE_ROOT:-$(dirname "$0")/../../../..}" && pwd)
mkdir -p "$work"
work=$(cd "$work" && pwd)

run() {
    local -a command=("$@")
    if [ -n "${S_BOOTSTRAP_RUNNER:-}" ]; then
        command=("$S_BOOTSTRAP_RUNNER" "${command[@]}")
    fi
    if command -v timeout >/dev/null 2>&1; then
        timeout "${S_BOOTSTRAP_TIMEOUT:-120}" "${command[@]}"
    else
        "${command[@]}"
    fi
}

cat > "$work/helper.s" <<'S'
package bootstrap_probe
func triple(int value) int { return value * 3 }
S
for offset in 4 9; do
    cat > "$work/main.s" <<S
package bootstrap_probe
func main(int input) int { return triple(input) + $offset }
S
    artifact="$work/program-$offset.sasm"
    binary="$work/program-$offset"
    rm -f "$artifact" "$binary"
    run "$compiler" --compile-unit "$artifact" "$work/main.s" "$work/helper.s"
    test -s "$artifact"
    test "$(head -n 1 "$artifact")" = '# S-NATIVE-AMD64-V1'
    # Emission must consume the artifact even after its input source is gone.
    rm "$work/main.s"
    run "$compiler" --emit-bin "$artifact" "$binary"
    sh "$root/misc/scripts/verify_true_selfhost.sh" "$binary"
    for input in 2 7; do
        status=0
        run "$binary" "$input" || status=$?
        wanted=$((input * 3 + offset))
        if [ "$status" -ne "$wanted" ]; then
            printf 'selfhost execution failed: input=%s offset=%s expected=%s actual=%s\n' \
                "$input" "$offset" "$wanted" "$status" >&2
            exit 1
        fi
    done
done
if cmp -s "$work/program-4.sasm" "$work/program-9.sasm"; then
    echo 'selfhost execution failed: assembly did not change with source' >&2
    exit 1
fi
echo "native compiler source dependence and execution verified: $compiler"
