#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-build.XXXXXX)
printf 'Native build artifacts=%s\n' "$work"
compiler="$root/bin/s_compiler"
driver="$root/bin/s"
source_file="$work/program with spaces.s"
binary="$work/native program"
cp "$root/test/native-build/program.s" "$source_file"
cat > "$work/forbidden-cc" <<'CC'
#!/bin/sh
printf '%s\n' 'native build invoked C compiler' >&2
exit 77
CC
chmod +x "$work/forbidden-cc"
export CC="$work/forbidden-cc"
timeout 30s "$compiler" build "$source_file" -o "$binary"
expect_status() {
    local executable=$1 input=$2 wanted=$3 actual=0
    timeout 5s "$executable" "$input" > "$work/run.out" 2> "$work/run.err" || actual=$?
    if [[ "$actual" != "$wanted" ]]; then
        printf 'input=%s expected status=%s got=%s\n' "$input" "$wanted" "$actual" >&2
        cat "$work/run.err" >&2
        exit 1
    fi
}
sha256sum "$binary" > "$work/before.sha256"
expect_status "$binary" 7 25
expect_status "$binary" 2 10
expect_status "$binary" -2 254
expect_status "$binary" 0 4
expect_status "$binary" bad 2
expect_status "$binary" 9223372036854775808 2
expect_status "$binary" -9223372036854775809 2
sha256sum "$binary" > "$work/after.sha256"
cmp "$work/before.sha256" "$work/after.sha256"
readelf -h "$binary" > "$work/elf.txt"
grep -q 'Advanced Micro Devices X86-64' "$work/elf.txt"
readelf -l "$binary" > "$work/segments.txt"
if grep -q INTERP "$work/segments.txt"; then echo 'unexpected dynamic interpreter' >&2; exit 1; fi
nm "$binary" > "$work/symbols.txt"
if grep -Eq 'seed_compile|runtime_execute|execute_source_main|execute_mir_graph' "$work/symbols.txt"; then
    echo 'native executable links compiler/interpreter' >&2; exit 1
fi
objdump -d "$binary" > "$work/disassembly.txt"
grep -q 'call' "$work/disassembly.txt"
grep -q 'imul' "$work/disassembly.txt"
S_MODULAR_COMPILER="$work/absent" timeout 30s "$driver" build "$source_file" -o "$work/driver program"
expect_status "$work/driver program" 7 25
expect_status "$work/driver program" 2 10
timeout 30s "$compiler" --emit-native-object "$source_file" "$work/program.o"
readelf -h "$work/program.o" > "$work/object.txt"
grep -q 'REL (Relocatable file)' "$work/object.txt"
cat > "$work/object-runner.c" <<'C'
#include <stdint.h>
extern int64_t s_native_entry(int64_t);
int main(void) {
    return s_native_entry(7) == 25 && s_native_entry(-2) == -2 ? 0 : 1;
}
C
cc -std=c11 -Wall -Wextra -Werror "$work/object-runner.c" "$work/program.o" -o "$work/object-runner"
"$work/object-runner"
sed 's/product + 4/product + 9/' "$source_file" > "$work/changed.s"
timeout 30s "$compiler" build "$work/changed.s" -o "$work/changed"
expect_status "$work/changed" 7 30
sed 's/left \* right/left - right/' "$source_file" > "$work/subtract.s"
timeout 30s "$compiler" build "$work/subtract.s" -o "$work/subtract"
expect_status "$work/subtract" 7 8
printf 'package main\nfunc main() int { if true { return 1 }; return 2 }\n' > "$work/unsupported.s"
if timeout 10s "$compiler" build "$work/unsupported.s" -o "$work/unsupported"; then
    echo 'unsupported source accepted' >&2; exit 1
fi
test ! -e "$work/unsupported"
cat > "$work/shadowed-call.s" <<'SHADOW'
package main
func helper(int value) int { return value + 1 }
func main(int helper) int { return helper(2) }
SHADOW
for mode in build --emit-amd64 --emit-native-object; do
    rejected_output="$work/shadowed-$mode"
    rejected_log="$work/shadowed-$mode.log"
    if [ "$mode" = build ]; then
        if timeout 10s "$compiler" build "$work/shadowed-call.s" -o "$rejected_output" > "$rejected_log" 2>&1; then
            echo 'production build called a function hidden by an integer parameter' >&2; exit 1
        fi
    elif timeout 10s "$compiler" "$mode" "$work/shadowed-call.s" "$rejected_output" > "$rejected_log" 2>&1; then
        echo 'emission accepted a call through an integer binding' >&2; exit 1
    fi
    grep -Fq 'integer binding is not callable: helper' "$rejected_log"
    test ! -e "$rejected_output"
done
cat > "$work/binding-initializer.s" <<'INITIALIZER'
package main
func helper(int value) int { return value + 1 }
func main(int input) int { helper := helper(input); return helper }
INITIALIZER
timeout 30s "$compiler" build "$work/binding-initializer.s" -o "$work/binding-initializer"
expect_status "$work/binding-initializer" 7 8
expect_status "$work/binding-initializer" 2 3
printf 'package main\nfunc main() int { return 7 }\000this_is_unsupported\n' > "$work/nul.s"
if timeout 10s "$compiler" build "$work/nul.s" -o "$work/nul"; then
    echo 'source containing embedded NUL was silently truncated' >&2; exit 1
fi
test ! -e "$work/nul"
for mode in --emit-amd64 --emit-amd64-executable; do
    if S_TARGET_OS=darwin S_TARGET_ARCH=arm64 timeout 10s "$compiler" "$mode" "$source_file" "$work/wrong-target.s"; then
        echo 'assembly emission ignored configured target' >&2; exit 1
    fi
    test ! -e "$work/wrong-target.s"
done
# Failed compilation and tool failures must preserve the previous artifact.
cp "$binary" "$work/preserved"
if timeout 10s "$compiler" build "$work/unsupported.s" -o "$work/preserved"; then exit 1; fi
cmp "$binary" "$work/preserved"
if S_AS=/bin/false timeout 10s "$compiler" build "$source_file" -o "$work/preserved"; then exit 1; fi
cmp "$binary" "$work/preserved"
if S_LD=/bin/false timeout 10s "$compiler" build "$source_file" -o "$work/preserved"; then exit 1; fi
cmp "$binary" "$work/preserved"
cp "$source_file" "$work/source-before"
if timeout 10s "$compiler" build "$source_file" -o "$source_file"; then exit 1; fi
cmp "$source_file" "$work/source-before"
ln "$source_file" "$work/hardlink.s"
if timeout 10s "$compiler" build "$source_file" -o "$work/hardlink.s"; then exit 1; fi
cmp "$source_file" "$work/source-before"
ln -s "$source_file" "$work/symlink.s"
if timeout 10s "$compiler" build "$source_file" -o "$work/symlink.s"; then exit 1; fi
cmp "$source_file" "$work/source-before"
timeout 30s "$compiler" build "$source_file" -o "$work/nested/new/program"
expect_status "$work/nested/new/program" 7 25
if find "$work" -type d -name '.s-native-*' | read -r _; then
    echo 'native build leaked temporary directory' >&2; exit 1
fi
printf 'P0.3 production Native build and P0.4 runtime input: PASS\n'
