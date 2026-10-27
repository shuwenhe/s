#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-intrinsic.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cd "$root"
bin/s_seed --compile-native-unit "$work/validate.ir" src/cmd/compile/internal/mir/program.s src/cmd/compile/internal/mir/program_enum.s src/cmd/compile/internal/ssa/program.s src/cmd/compile/internal/ssa/function_lower.s test/native-intrinsic/validate.s
S_SOURCE_ROOT="$root" bin/s_seed --emit-standalone-amd64 "$work/validate.ir" "$work/validate"
"$work/validate"
bin/s_seed --compile-unit "$work/generate.ir" src/cmd/compile/internal/ssa/program.s src/cmd/compile/internal/codegen/amd64_program.s test/native-intrinsic/generate.s
bin/s_seed --emit-bin "$work/generate.ir" "$work/generate"
"$work/generate" > "$work/program.s"
as --64 -o "$work/program.o" "$work/program.s"
ld -m elf_x86_64 -nostdlib -o "$work/program" "$work/program.o"
head -c 131073 /dev/zero > "$work/large"
mkdir "$work/bin"
printf '#!/bin/sh\nexit 23\n' > "$work/bin/native-test-command"
chmod +x "$work/bin/native-test-command"
status=0; PATH="$work/bin" S_NATIVE_INTRINSIC_TEST=env-value "$work/program" "$work/written" "$work/large" "$work" > "$work/stdout" 2> "$work/stderr" || status=$?
test "$status" -eq 11
test "$(cat "$work/written.renamed")" = 'native 世界'
test "$(cat "$work/stdout")" = 'native 世界'
test "$(cat "$work/stderr")" = 'env-value'
test -x "$work/written.renamed"
test "$(find "$work" -mindepth 1 -maxdepth 1 -type d -name 's-native-*' | wc -l)" -eq 1
status=0; PATH="$work/missing-bin" S_NATIVE_INTRINSIC_TEST=env-value "$work/program" "$work/written" "$work/large" "$work" > "$work/missing-stdout" 2> "$work/missing-stderr" || status=$?
test "$status" -eq 10
"$work/generate" panic > "$work/panic.s"
as --64 -o "$work/panic.o" "$work/panic.s"
ld -m elf_x86_64 -nostdlib -o "$work/panic" "$work/panic.o"
status=0; PATH="$work/bin" S_NATIVE_INTRINSIC_TEST=env-value "$work/panic" "$work/written" "$work/large" "$work" > "$work/panic-stdout" 2> "$work/panic-stderr" || status=$?
test "$status" -eq 101
test "$(tail -n 1 "$work/panic-stderr")" = 'native panic'
echo 'native intrinsic strict MIR/SSA validation, argv, read/write, environment, printing and int conversion: PASS'
