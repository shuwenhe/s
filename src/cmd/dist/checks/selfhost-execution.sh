#!/usr/bin/env bash
# Exercise the compiler's source -> native artifact -> executable boundary.
set -euo pipefail

# Report completed checks; never advance past a failed operation.
check_progress() {
    [ "${S_BOOTSTRAP_PROGRESS:-0}" = 1 ] || return 0
    progress_done=$1
    progress_total=$2
    progress_label=$3
    progress_bar=
    progress_index=0
    while [ "$progress_index" -lt 20 ]; do
        if [ "$progress_index" -lt "$((progress_done * 20 / progress_total))" ]; then
            progress_bar="${progress_bar}#"
        else
            progress_bar="${progress_bar}-"
        fi
        progress_index=$((progress_index + 1))
    done
    printf '  CHECK [%s] %s/%s %s\n' "$progress_bar" "$progress_done" "$progress_total" "$progress_label" >&2
}
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
execution_done=0
check_progress 0 9 "source dependence and execution: $compiler"
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
    execution_done=$((execution_done + 1))
    check_progress "$execution_done" 9 "offset=$offset artifact validated"
    # Emission must consume the artifact even after its input source is gone.
    rm "$work/main.s"
    run "$compiler" --emit-bin "$artifact" "$binary"
    sh "$root/misc/scripts/verify_true_selfhost.sh" "$binary"
    execution_done=$((execution_done + 1))
    check_progress "$execution_done" 9 "offset=$offset executable verified"
    for input in 2 7; do
        status=0
        run "$binary" "$input" || status=$?
        wanted=$((input * 3 + offset))
        if [ "$status" -ne "$wanted" ]; then
            printf 'selfhost execution failed: input=%s offset=%s expected=%s actual=%s\n' \
                "$input" "$offset" "$wanted" "$status" >&2
            exit 1
        fi
        execution_done=$((execution_done + 1))
        check_progress "$execution_done" 9 "offset=$offset input=$input result verified"
    done
done
if cmp -s "$work/program-4.sasm" "$work/program-9.sasm"; then
    echo 'selfhost execution failed: assembly did not change with source' >&2
    exit 1
fi
check_progress 9 9 "source dependence verified"
echo "native compiler source dependence and execution verified: $compiler"
