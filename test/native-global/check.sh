#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-global.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cd "$root"
bin/s_seed --compile-native-unit "$work/validate.ir" src/cmd/compile/internal/mir/program.s src/cmd/compile/internal/mir/program_enum.s src/cmd/compile/internal/ssa/program.s src/cmd/compile/internal/ssa/function_lower.s test/native-global/validate.s
S_SOURCE_ROOT="$root" bin/s_seed --emit-standalone-amd64 "$work/validate.ir" "$work/validate"
"$work/validate"
bin/s_seed --compile-unit "$work/generate.ir" src/cmd/compile/internal/ssa/program.s src/cmd/compile/internal/codegen/amd64_program.s test/native-global/generate.s
bin/s_seed --emit-bin "$work/generate.ir" "$work/generate"
"$work/generate" > "$work/main.s"
as --64 -o "$work/main.o" "$work/main.s"
ld -m elf_x86_64 -nostdlib -o "$work/main" "$work/main.o"
status=0; "$work/main" || status=$?
test "$status" -eq 85
"$work/generate" object > "$work/library.s"
cat >> "$work/library.s" <<'S'
.text
.globl _start
_start:
 andq $-16,%rsp
 call s_native_initialize_globals
 call s_native_entry
 call s_native_initialize_globals
 call s_native_entry
 movq %rax,%rdi
 movl $60,%eax
 syscall
S
as --64 -o "$work/library.o" "$work/library.s"
ld -m elf_x86_64 -nostdlib -o "$work/library" "$work/library.o"
status=0; "$work/library" || status=$?
test "$status" -eq 86
echo 'native globals typed MIR/SSA validation, dependency initialization, mutation and library idempotence: PASS'
