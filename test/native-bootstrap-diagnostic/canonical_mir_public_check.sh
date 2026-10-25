#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-canonical-mir-public.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo "canonical MIR artifacts: $work" >&2; fi' EXIT
S_SOURCE_ROOT="$root" "$root/src/cmd/dist/source_closure.sh" src/cmd/compile/main.s "$work/sources"
for source in src/cmd/compile/internal/compiler/compiler.s src/cmd/compile/internal/compiler/bridge.s; do
    if ! grep -Fxq "$source" "$work/sources"; then
        echo "canonical MIR definition missing from production closure: $source" >&2
        exit 1
    fi
done
compiler=${1:-"$root/bin/s_compiler"}
sh "$root/misc/scripts/verify_true_selfhost.sh" "$compiler"
cat > "$work/input.s" <<'S'
package main
func triple(int value) int { return value * 3 }
func main(int value) int { return triple(value) + 4 }
S
"$compiler" "$work/input.s" "$work/output.mir"
grep -Fxq 'mir-program-v1 package=main entry=main.main' "$work/output.mir"
grep -Fxq 'function main.triple external=false' "$work/output.mir"
grep -Fxq 'function main.main external=false' "$work/output.mir"
grep -q '^instruction mul ' "$work/output.mir"
grep -q '^instruction call .*symbol=main.triple$' "$work/output.mir"
grep -q '^instruction const_int .*integer=4 ' "$work/output.mir"
sed 's/) + 4/) + 9/' "$work/input.s" > "$work/changed.s"
"$compiler" "$work/changed.s" "$work/changed.mir"
! cmp -s "$work/output.mir" "$work/changed.mir"
grep -q '^instruction const_int .*integer=9 ' "$work/changed.mir"
# The actual MIR consumer path must still produce input-dependent machine code.
"$compiler" --compile-unit "$work/program.sasm" "$work/input.s"
"$compiler" --emit-bin "$work/program.sasm" "$work/program"
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/program"
for pair in '7 25' '2 10'; do
    read -r argument wanted <<< "$pair"
    status=0; "$work/program" "$argument" || status=$?
    test "$status" -eq "$wanted"
done
cat > "$work/invalid.s" <<'S'
package main
func main() int { return missing(1) }
S
cp "$work/output.mir" "$work/saved"
if "$compiler" "$work/invalid.s" "$work/output.mir" > "$work/invalid.log" 2>&1; then
    echo 'canonical MIR entrypoint accepted an unresolved call' >&2; exit 1
fi
cmp "$work/output.mir" "$work/saved"
echo 'canonical MIR closure, source-dependent dump and MIR/SSA/native handoff: PASS'
