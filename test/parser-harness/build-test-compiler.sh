#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d /tmp/s-harness-compiler.XXXXXXXX)
printf 'Test compiler artifacts=%s\n' "$work"
cd "$root"
git rev-parse HEAD > "$work/commit.txt"
S_SOURCE_ROOT="$root" timeout 60s bash src/cmd/dist/source_closure.sh \
    src/cmd/compile/main.s "$work/sources.txt"
mapfile -t sources < "$work/sources.txt"
sha256sum bin/s_seed "${sources[@]}" > "$work/input-hashes.txt"
printf '%q ' "$root/bin/s_seed" --compile-unit "$work/compiler.ir" "${sources[@]}" > "$work/commands.txt"
printf '\n' >> "$work/commands.txt"
status=0
timeout 60s "$root/bin/s_seed" --compile-unit "$work/compiler.ir" "${sources[@]}" \
    > "$work/compile.log" 2>&1 || status=$?
printf '%s\n' "$status" > "$work/compile.exit"
if [[ "$status" != 0 ]]; then cat "$work/compile.log" >&2; exit "$status"; fi
printf '%q ' "$root/bin/s_seed" --emit-bin "$work/compiler.ir" "$work/compiler" >> "$work/commands.txt"
printf '\n' >> "$work/commands.txt"
status=0
S_SOURCE_ROOT="$root" timeout 60s "$root/bin/s_seed" --emit-bin "$work/compiler.ir" "$work/compiler" \
    > "$work/emit.log" 2>&1 || status=$?
printf '%s\n' "$status" > "$work/emit.exit"
if [[ "$status" != 0 ]]; then cat "$work/emit.log" >&2; exit "$status"; fi
printf 'Seed-hosted test compiler=%s/compiler\n' "$work"
