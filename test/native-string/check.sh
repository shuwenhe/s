#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-string.XXXXXX)
trap 'rm -rf "$work"' EXIT
cd "$root"
bin/s_seed --compile-unit "$work/generate.ir" src/cmd/compile/internal/mir/program.s src/cmd/compile/internal/mir/program_enum.s src/cmd/compile/internal/ssa/program.s src/cmd/compile/internal/ssa/function_lower.s src/cmd/compile/internal/codegen/amd64_program.s test/native-string/generate.s
bin/s_seed --emit-bin "$work/generate.ir" "$work/generate"
bin/s_seed --compile-native-unit "$work/validate.ir" src/cmd/compile/internal/mir/program.s src/cmd/compile/internal/mir/program_enum.s src/cmd/compile/internal/ssa/program.s src/cmd/compile/internal/ssa/function_lower.s test/native-string/validate.s
S_SOURCE_ROOT="$root" bin/s_seed --emit-standalone-amd64 "$work/validate.ir" "$work/validate"
"$work/validate"
"$work/generate" > "$work/program.s"
as --64 -o "$work/program.o" "$work/program.s"
ld -m elf_x86_64 -nostdlib -o "$work/program" "$work/program.o"
status=0; "$work/program" || status=$?
test "$status" -eq 120
"$work/generate" negative > "$work/bounds.s"
as --64 -o "$work/bounds.o" "$work/bounds.s"
ld -m elf_x86_64 -nostdlib -o "$work/bounds" "$work/bounds.o"
status=0; "$work/bounds" || status=$?
test "$status" -eq 16
echo 'native string MIR/SSA rejection and literal/concat/byte-length/content comparisons/access/defaults execution: PASS'
