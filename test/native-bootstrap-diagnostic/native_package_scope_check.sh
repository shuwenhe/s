#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-package-scope.XXXXXX)
trap 'rm -rf "$work"' EXIT
if ! make -C "$root" compiler > "$work/build.log" 2>&1; then
    tail -25 "$work/build.log" >&2
    exit 1
fi
compiler="$root/bin/s_compiler"
cat > "$work/main.s" <<'S'
package app
import calc "lib.alpha"
func main(int input) int { return calc.compute(input) + local(input) }
func local(int input) int { return input + 1 }
S
cat > "$work/local.s" <<'S'
package app
import calc "lib.beta"
func unused(int input) int { return calc.compute(input) }
S
cat > "$work/alpha.s" <<'S'
package lib.alpha
func compute(int input) int { return local(input) * 3 }
func local(int input) int { return input + 2 }
S
cat > "$work/beta.s" <<'S'
package lib.beta
func compute(int input) int { return input + 100 }
S
compile() {
    timeout 30 "$compiler" --compile-unit "$work/program.sasm" \
        "$work/main.s" "$work/local.s" "$work/alpha.s" "$work/beta.s"
    timeout 30 "$compiler" --emit-bin "$work/program.sasm" "$work/program"
    sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/program"
}
run() {
    local status=0
    "$work/program" "$1" || status=$?
    test "$status" -eq "$2"
}
compile
run 7 35
run 2 15
# The second file in app has the same alias but a different target. It must
# neither change main's calls nor resolve its own call using main's imports.
sed 's/return calc.compute(input) + local(input)/return calc.compute(input) + unused(input)/' \
    "$work/main.s" > "$work/new-main.s"
mv "$work/new-main.s" "$work/main.s"
compile
run 7 134
cat > "$work/main.s" <<'S'
package app
import (
    "lib.alpha",
    "lib.beta" as second,
)
func main(int input) int { return alpha.compute(input) + second.compute(input) }
S
compile
run 7 134
cat > "$work/main.s" <<'S'
package app
use lib.alpha as calc
func main(int input) int { return calc.compute(input) }
S
compile
run 7 27
cp "$work/program.sasm" "$work/saved"
reject() {
    local status=0
    timeout 30 "$compiler" --compile-unit "$work/program.sasm" "$work/bad.s" \
        "$work/alpha.s" "$work/beta.s" > "$work/rejected.log" 2>&1 || status=$?
    if [ "$status" -ne 1 ]; then
        cat "$work/rejected.log" >&2
        echo "expected scope rejection, got status $status" >&2; exit 1
    fi
    grep -Fq "$1" "$work/rejected.log"
    cmp "$work/program.sasm" "$work/saved"
}
cat > "$work/bad.s" <<'S'
package app
import calc "lib.alpha"
func main(int calc) int { return calc.compute(2) }
S
reject 'integer binding is not callable: calc'
cat > "$work/bad.s" <<'S'
package app
func main() int { return compute(2) }
S
reject 'unknown callee: app.compute'
cat > "$work/bad.s" <<'S'
package app
import calc "lib.alpha"
import calc "lib.beta"
func main() int { return calc.compute(2) }
S
reject 'duplicate import alias: calc'
cat > "$work/bad.s" <<'S'
package app
import missing "lib.absent"
func main() int { return 42 }
S
reject 'imported package not supplied: lib.absent'
# File-local imports cannot leak into another file of the same package.
cat > "$work/bad.s" <<'S'
package app
import calc "lib.alpha"
func main() int { return local() }
package app
func local() int { return calc.compute(2) }
S
reject 'unknown callee: calc.compute'
cat > "$work/bad.s" <<'S'
package app
func main() int { return lib.alpha.compute(2) }
S
reject 'callee package not imported: lib.alpha'
cat > "$work/bad.s" <<'S'
package app
import compute "lib.alpha"
func compute() int { return 42 }
func main() int { return compute() }
S
reject 'import alias conflicts with function: compute'
echo 'native package identity, file-local imports and call isolation: PASS'
