#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work="$root/.bootstrap/native-stage1-check"
mkdir -p "$work"
S_SOURCE_ROOT="$root" "$root/src/cmd/dist/source_closure.sh" src/cmd/compile/main.s "$work/sources"
sources=()
while IFS= read -r source; do sources+=("$root/$source"); done < "$work/sources"
"$root/bin/s_seed" --compile-native-unit "$work/stage1.ir" "${sources[@]}"
"$root/bin/s_seed" --emit-standalone-amd64 "$work/stage1.ir" "$work/stage1"
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/stage1"
mkdir -p "$work/emission"
printf 'keep\n' > "$work/emission/keep"
printf '# S-NATIVE-AMD64-V1\n.global _start\n_start: mov $60, %%rax; xor %%rdi, %%rdi; syscall\n' > "$work/emission/input.sasm"
# The native temporary-directory service is currently a stub. Until replaced,
# fail before writing files or running cleanup on the destination parent.
if timeout 30 "$work/stage1" --emit-bin "$work/emission/input.sasm" "$work/emission/program" > "$work/emission.log" 2>&1; then
    echo 'native temporary-directory fallback accepted' >&2; exit 1
fi
test "$(cat "$work/emission/keep")" = keep
printf 'package main\nfunc main(int value) int { return value * 3 + 4 }\n' > "$work/input.s"
timeout 30 "$work/stage1" --compile-unit "$work/program.sasm" "$work/input.s"
timeout 30 "$work/stage1" --emit-bin "$work/program.sasm" "$work/program"
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/program"
status=0; "$work/program" 7 || status=$?
test "$status" -eq 25
echo 'full-source native stage1 -> subset native ELF: PASS'
