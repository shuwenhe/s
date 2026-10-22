#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-artifact.XXXXXX)
trap 'rm -rf "$work"' EXIT
make -C "$root" compiler > "$work/build.log" 2>&1
compiler="$root/bin/s_compiler"
cat > "$work/helper.s" <<'S'
package main
func helper(int value) int { return value * 3 }
S
cat > "$work/main.s" <<'S'
package main
func main(int input) int { return helper(input) + 4 }
S
timeout 30 "$compiler" --compile-unit "$work/program.sasm" "$work/main.s" "$work/helper.s"
head -n 1 "$work/program.sasm" | grep -qx '# S-NATIVE-AMD64-V1'
! grep -q 'compiler_runtime.h' "$work/program.sasm"
cat > "$work/forbidden-cc" <<'SH'
#!/bin/sh
echo 'native artifact emission invoked a C compiler' >&2
exit 77
SH
chmod +x "$work/forbidden-cc"
export CC="$work/forbidden-cc"
timeout 30 "$compiler" --emit-bin "$work/program.sasm" "$work/program"
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/program"
for pair in '7 25' '2 10'; do
    read -r input wanted <<< "$pair"
    status=0
    "$work/program" "$input" || status=$?
    test "$status" -eq "$wanted"
done
# Outputs must depend on source, and emission must need only the artifact.
sed 's/input) + 4/input) + 9/' "$work/main.s" > "$work/changed.s"
"$compiler" --compile-unit "$work/changed.sasm" "$work/changed.s" "$work/helper.s"
! cmp -s "$work/program.sasm" "$work/changed.sasm"
rm "$work/main.s" "$work/helper.s" "$work/changed.s"
"$compiler" --emit-bin "$work/changed.sasm" "$work/changed"
status=0; "$work/changed" 7 || status=$?
test "$status" -eq 30
# Wrong protocols and aliases must leave existing outputs intact.
printf 'SSEED-TARGET-V1\n' > "$work/wrong.ir"
cp "$work/program" "$work/saved"
if "$compiler" --emit-bin "$work/wrong.ir" "$work/program" > "$work/reject.log" 2>&1; then
    echo 'seed IR accepted as native artifact' >&2; exit 1
fi
cmp "$work/program" "$work/saved"
ln "$work/program.sasm" "$work/alias.sasm"
if "$compiler" --emit-bin "$work/program.sasm" "$work/alias.sasm"; then
    echo 'artifact overwritten through alias' >&2; exit 1
fi
cat > "$work/unsupported.s" <<'S'
package main
func main() int { if true { return 1 }; return 2 }
S
if "$compiler" --compile-unit "$work/rejected.sasm" "$work/unsupported.s"; then
    echo 'unsupported source accepted' >&2; exit 1
fi
test ! -e "$work/rejected.sasm"
if "$compiler" --compile-unit "$work/unsupported.s" "$work/unsupported.s"; then
    echo 'source overwritten' >&2; exit 1
fi
cp "$work/unsupported.s" "$work/source-saved"
ln "$work/unsupported.s" "$work/source-alias"
if "$compiler" --compile-unit "$work/source-alias" "$work/unsupported.s"; then
    echo 'source overwritten through hard link' >&2; exit 1
fi
cmp "$work/source-saved" "$work/unsupported.s"
cat > "$work/other.s" <<'S'
package other
func helper() int { return 3 }
S
if "$compiler" --compile-unit "$work/packages.sasm" "$work/unsupported.s" "$work/other.s"; then
    echo 'different packages merged into one namespace' >&2; exit 1
fi
test ! -e "$work/packages.sasm"
# Assembler failure must preserve an already installed executable.
if S_AS=false "$compiler" --emit-bin "$work/program.sasm" "$work/program"; then
    echo 'assembler failure ignored' >&2; exit 1
fi
cmp "$work/program" "$work/saved"
echo 'S native compile-unit -> artifact -> ELF: PASS'
