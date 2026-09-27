#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage5-input-authority.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

cat >"$work/minimal.s" <<'SRC'
package main
func main() int { return 0 }
SRC

make -C "$root" compiler >/dev/null

report="$work/stage5-proof.txt"
"$root/bin/s_compiler" stage5-name-resolution-proof "$work/minimal.s" "$report"

grep -qx 'S5.1=PASS' "$report"
grep -qx 'S5.1.evidence=canonical entry parsed source to AST and reached Stage 5 resolver entry' "$report"
grep -qx 'stage=5' "$report"
grep -qx 'input-authority=canonical-ast' "$report"
grep -qx 'entry-authority=canonical-compile-path' "$report"
grep -qx 'ast-present=yes' "$report"
grep -qx 'resolver-entry-reached=yes' "$report"
if grep -Eq '^S5\.[3-9]=PASS|DeclarationRef|CanonicalTypeRef|MIR|qualified-lookup=yes|declaration-candidate=yes' "$report"; then
  echo "S5.1 proof leaked later-stage claims" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage5 input authority proof self-test passed"
