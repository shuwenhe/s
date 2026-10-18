#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-codegen.XXXXXX)
printf 'Native SSA codegen artifacts=%s\n' "$work"
cd "$root"
sources=(src/cmd/compile/internal/ssa/program.s src/cmd/compile/internal/codegen/amd64_program.s test/native-codegen/generate.s)
sha256sum "${sources[@]}" bin/s_seed > "$work/input-hashes.txt"
as --version > "$work/assembler-version.txt"
ld --version > "$work/linker-version.txt"
timeout 30s ./bin/s_seed --compile-unit "$work/generator.ir" "${sources[@]}"
S_SOURCE_ROOT="$root" timeout 60s ./bin/s_seed --emit-bin "$work/generator.ir" "$work/generator"
prepare() {
    local mode=$1
    if [[ -f "$work/$mode/native" ]]; then return; fi
    mkdir -p "$work/$mode"
    timeout 10s "$work/generator" "$mode" > "$work/$mode/program.s"
    as -o "$work/$mode/program.o" "$work/$mode/program.s"
    "${CC:-cc}" -std=c11 -Wall -Wextra -Werror -O2 \
        test/native-codegen/runner.c "$work/$mode/program.o" -o "$work/$mode/native"
}
expect() {
    local mode=$1 input=$2 wanted=$3 actual
    prepare "$mode"
    actual=$(timeout 10s "$work/$mode/native" "$input")
    if [[ "$actual" != "$wanted" ]]; then
        printf '%s input=%s: wanted %s, got %s\n' "$mode" "$input" "$wanted" "$actual" >&2
        exit 1
    fi
}
# Several inputs use the very same linked object and executable.
expect base 7 32
expect base -2 -4
expect base 0 4
expect changed 7 37
expect subtract 7 24
expect copy 7 32
expect nested 7 47
expect nested -2 2
expect min 0 -9223372036854775808
expect max 0 9223372036854775807
expect divide 7 -2
expect divide -7 2
expect modulo 7 1
expect modulo -7 -1
expect divide -9223372036854775808 3074457345618258602
expect modulo -9223372036854775808 -2
expect positive_divide -7 -2
expect positive_modulo -7 -1
expect divide_minus_one -9223372036854775808 -9223372036854775808
expect modulo_minus_one -9223372036854775808 0
expect divide_minus_one 9223372036854775807 -9223372036854775807
expect wrap 9223372036854775807 -9223372036854775808
expect wrap -9223372036854775808 -9223372036854775807
expect subwrap -9223372036854775808 9223372036854775807
expect mulwrap 9223372036854775807 9223372036854775805
expect call7 7 146
expect call7 -2 137
expect call8 7 210
expect call8 -2 201
expect incoming8 7 210
expect incoming8 -2 201
expect void_call 0 17
prepare divide_zero
divide_status=0
timeout 10s "$work/divide_zero/native" 1 > "$work/divide_zero/output" || divide_status=$?
test "$divide_status" -eq 86
test ! -s "$work/divide_zero/output"
mkdir -p "$work/void"
timeout 10s "$work/generator" void > "$work/void/program.s"
as -o "$work/void/program.o" "$work/void/program.s"
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -O2 \
    test/native-codegen/void_runner.c "$work/void/program.o" -o "$work/void/native"
timeout 10s "$work/void/native"
for mode in invalid_op undefined bad_arity bad_copy_arity const_operands forward_operand bad_parameter_type \
            bad_param missing_param duplicate_param param_operands \
            bad_type bad_return multiple_results missing_edge unknown_target bad_call_result \
            void_operand void_use multiple_blocks; do
    if timeout 10s "$work/generator" "$mode" > "$work/$mode.s" 2> "$work/$mode.log"; then
        printf '%s unexpectedly accepted\n' "$mode" >&2
        exit 1
    fi
    test ! -s "$work/$mode.s"
    test -s "$work/$mode.log"
done
# Test instrumentation checks actual entry rsp alignment at every generated
# function, including the outgoing odd/even stack-argument calls. The original
# objects above are separately linked and executed without instrumentation.
for mode in call7 call8 nested; do
    python3 - "$work/$mode/program.s" "$work/$mode/alignment.s" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
text = re.sub(r'^(s_native_fn_[0-9]+:)$', r'\1\n  movq %rsp, %r11\n  andq $15, %r11\n  cmpq $8, %r11\n  jne .Ltest_bad_alignment', text, flags=re.M)
text += '\n.text\n.Ltest_bad_alignment:\n  movl $91, %edi\n  movl $60, %eax\n  syscall\n  ud2\n'
Path(sys.argv[2]).write_text(text)
PY
    as -o "$work/$mode/alignment.o" "$work/$mode/alignment.s"
    "${CC:-cc}" -std=c11 -Wall -Wextra -Werror -O2 \
        test/native-codegen/runner.c "$work/$mode/alignment.o" -o "$work/$mode/alignment"
    timeout 10s "$work/$mode/alignment" 7 > "$work/$mode/alignment.out"
done
readelf -h "$work/base/program.o" > "$work/base/elf-header.txt"
readelf -Ws "$work/base/program.o" > "$work/base/symbols.txt"
readelf -r "$work/base/program.o" > "$work/base/relocations.txt"
objdump -dr "$work/base/program.o" > "$work/base/disassembly.txt"
objdump -dr "$work/divide/program.o" > "$work/divide/disassembly.txt"
grep -Eq 'Class:.*ELF64' "$work/base/elf-header.txt"
grep -Eq 'Type:.*REL ' "$work/base/elf-header.txt"
grep -Eq 'Machine:.*X86-64' "$work/base/elf-header.txt"
grep -q 's_native_entry' "$work/base/symbols.txt"
grep -q 's_native_fn_2' "$work/base/symbols.txt"
grep -Eq 'R_X86_64_(PLT32|PC32).*s_native_fn_1' "$work/base/relocations.txt"
grep -q 'imul' "$work/base/disassembly.txt"
grep -q 'call' "$work/base/disassembly.txt"
grep -q 'idiv' "$work/divide/disassembly.txt"
# A sparse trillion-valued ID must still produce a tiny position-based frame.
grep -q 'subq \$48, %rsp' "$work/base/program.s"
if grep -Eq '1000000000000|unsafe|symbol|forward' "$work/base/program.s"; then
    printf 'Source identity leaked into assembler or frame size\n' >&2
    exit 1
fi
startup_prepare() {
    local mode=$1
    mkdir -p "$work/startup-$mode"
    timeout 10s "$work/generator" "$mode" startup > "$work/startup-$mode/program.s"
    as -o "$work/startup-$mode/program.o" "$work/startup-$mode/program.s"
    ld -o "$work/startup-$mode/native" "$work/startup-$mode/program.o"
}
startup_status() {
    local mode=$1 wanted=$2 actual=0
    shift 2
    timeout 10s "$work/startup-$mode/native" "$@" || actual=$?
    if [[ "$actual" -ne "$wanted" ]]; then
        printf 'startup %s expected %s got %s\n' "$mode" "$wanted" "$actual" >&2
        exit 1
    fi
}
startup_prepare identity
startup_status identity 7 7
startup_status identity 7 +7
startup_status identity 249 -7
startup_status identity 0 0
startup_status identity 0 -0
startup_status identity 255 9223372036854775807
startup_status identity 0 -9223372036854775808
startup_status identity 7 0007
startup_status identity 2
startup_status identity 2 1 2
for input in '' '+' '-' ' 7' '7 ' '7x' '--7' '+-7' '0x7' '9223372036854775808' \
             '-9223372036854775809' '18446744073709551616' '999999999999999999999999999999999'; do
    startup_status identity 2 "$input"
done
startup_prepare zero
startup_status zero 17
startup_prepare void
startup_status void 0
startup_prepare divide_zero
startup_status divide_zero 86 1
if timeout 10s "$work/generator" incoming8 startup > "$work/bad-startup.s" 2> "$work/bad-startup.log"; then
    printf 'Startup with eight-parameter entry unexpectedly accepted\n' >&2
    exit 1
fi
test ! -s "$work/bad-startup.s"
test -s "$work/bad-startup.log"
readelf -l "$work/startup-identity/native" > "$work/startup-identity/segments.txt"
readelf -d "$work/startup-identity/native" > "$work/startup-identity/dynamic.txt"
if grep -q INTERP "$work/startup-identity/segments.txt"; then exit 1; fi
grep -q 'There is no dynamic section' "$work/startup-identity/dynamic.txt"
printf 'SSA -> S AMD64 instruction selection -> GNU as ELF object -> ABI harness: PASS\n'
printf 'Register/stack parameters, calls/live values, signed arithmetic, rejection and ELF checks: PASS\n'
printf 'GNU ld standalone startup, strict runtime int64 argv and no dynamic dependencies: PASS\n'
