#!/usr/bin/env bash
# Native bootstrap: the C seed is used only to produce stage1.
# Later stages exchange versioned amd64 assembly, never seed IR or C.
set -euo pipefail

root=$(cd "${S_SOURCE_ROOT:-$(pwd)}" && pwd)
output_dir=${1:?usage: native-bootstrap-no-manifest.sh OUTPUT_DIR}
mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)
rm -f "$output_dir/.complete"
export S_SOURCE_ROOT="$root"
export S_TARGET_OS=${S_TARGET_OS:-$(uname -s | tr '[:upper:]' '[:lower:]')}
export S_TARGET_ARCH=${S_TARGET_ARCH:-$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')}
timeout_seconds=${S_BOOTSTRAP_TIMEOUT:-1200}
verify="$root/misc/scripts/verify_true_selfhost.sh"
seed="$root/bin/s_seed"

fail() { printf 'native bootstrap failed: %s\n' "$*" >&2; exit 1; }
[ "$S_TARGET_OS/$S_TARGET_ARCH" = linux/amd64 ] || fail 'only Linux/amd64 is supported'
[ -x "$seed" ] || fail "seed compiler not found: $seed"
[ -f "$root/src/cmd/compile/main.s" ] || fail 'main entry point not found'

run_stage() {
    local -a command=("$@")
    if [ -n "${S_BOOTSTRAP_RUNNER:-}" ]; then
        command=("$S_BOOTSTRAP_RUNNER" "${command[@]}")
    fi
    if command -v timeout >/dev/null 2>&1; then
        timeout "$timeout_seconds" "${command[@]}"
    else
        "${command[@]}"
    fi
}

printf '=== S Native Bootstrap (Import-Driven Model) ===\nSource Root: %s\nOutput Dir: %s\n' "$root" "$output_dir"
closure="$output_dir/stage1.sources"
"$root/src/cmd/dist/source_closure.sh" src/cmd/compile/main.s "$closure"
sources=()
while IFS= read -r source; do
    [ -n "$source" ] && sources+=("$root/$source")
done < "$closure"
[ "${#sources[@]}" -gt 0 ] || fail 'empty source closure'
printf 'Resolved source closure: %s files\n' "${#sources[@]}"
sha256sum "${sources[@]}" > "$output_dir/source-sha256"

printf '[1/3] Seed -> native stage1\n'
"$seed" --compile-native-unit "$output_dir/stage1.ir" "${sources[@]}" 2>&1 | tee "$output_dir/stage1-compile.log"
test -s "$output_dir/stage1.ir" || fail 'stage1 seed IR missing or empty'
# --emit-bin creates a C interpreter wrapper. It is deliberately excluded.
"$seed" --emit-standalone-amd64 "$output_dir/stage1.ir" "$output_dir/stage1" 2>&1 | tee "$output_dir/stage1-emit.log"
sh "$verify" "$output_dir/stage1" 2>&1 | tee "$output_dir/stage1-verify.log"

for stage in 2 3; do
    previous=$((stage - 1))
    producer="$output_dir/stage$previous"
    artifact="$output_dir/stage$stage.sasm"
    binary="$output_dir/stage$stage"
    # Remove stale intermediates before a producer can report success.
    rm -f "$artifact" "$binary"
    printf '[%s/3] stage%s -> stage%s\n' "$stage" "$previous" "$stage"
    run_stage "$producer" --compile-unit "$artifact" "${sources[@]}" 2>&1 | tee "$output_dir/stage$stage-compile.log"
    test -s "$artifact" || fail "stage$stage assembly artifact missing or empty"
    [ "$(head -n 1 "$artifact")" = '# S-NATIVE-AMD64-V1' ] || fail "stage$stage returned an incompatible artifact"
    run_stage "$producer" --emit-bin "$artifact" "$binary" 2>&1 | tee "$output_dir/stage$stage-emit.log"
    sh "$verify" "$binary" 2>&1 | tee "$output_dir/stage$stage-verify.log"
done

cmp -s "$output_dir/stage2.sasm" "$output_dir/stage3.sasm" || fail 'stage2/stage3 assembly did not converge'
cmp -s "$output_dir/stage2" "$output_dir/stage3" || fail 'stage2/stage3 binaries did not converge'
for stage in 2 3; do
    bash "$root/src/cmd/dist/checks/selfhost-execution.sh" \
        "$output_dir/stage$stage" "$output_dir/stage$stage-execution" \
        2>&1 | tee "$output_dir/stage$stage-execution.log"
done
sha256sum "${sources[@]}" > "$output_dir/source-sha256.after"
cmp -s "$output_dir/source-sha256" "$output_dir/source-sha256.after" || fail 'compiler sources changed during bootstrap'
touch "$output_dir/.complete"
printf 'Native bootstrap verified: seed -> stage1 -> stage2 == stage3\n'
