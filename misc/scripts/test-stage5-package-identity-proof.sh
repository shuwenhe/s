#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage5-package-identity.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

cat >"$work/package_alpha.s" <<'SRC'
package alpha
func main() int { return 0 }
SRC

make -C "$root" compiler >/dev/null

report1="$work/stage5-package-1.txt"
report2="$work/stage5-package-2.txt"
"$root/bin/s_compiler" stage5-name-resolution-proof "$work/package_alpha.s" "$report1"
"$root/bin/s_compiler" stage5-name-resolution-proof "$work/package_alpha.s" "$report2"

grep -qx 'S5.1=PASS' "$report1"
grep -qx 'S5.2=PASS' "$report1"
grep -qx 'S5.2.package-identity=alpha' "$report1"
grep -qx 'S5.2.identity-source=canonical-stage5-input' "$report1"
grep -qx 'S5.2.identity-stable=yes' "$report1"
grep -qx 'S5.2.evidence=canonical Stage 5 input has unique package identity alpha' "$report1"

identity1=$(sed -n 's/^S5.2.package-identity=//p' "$report1")
identity2=$(sed -n 's/^S5.2.package-identity=//p' "$report2")
test "$identity1" = alpha
test "$identity1" = "$identity2"

if grep -Eq '^S5\.[3-9]=PASS|import-registration|qualified-lookup|declaration-candidate|DeclarationRef|CanonicalTypeRef|MIR' "$report1"; then
  echo "S5.2 proof leaked later-stage claims" >&2
  cat "$report1" >&2
  exit 1
fi

echo "stage5 package identity proof self-test passed"
