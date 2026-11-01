#!/usr/bin/env bash
# Bootstrap discovery must follow every import spelling accepted by S.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-source-closure-import.XXXXXX)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/src/app" "$work/src/deps"
for dependency in inline first second aliased single bare bare_group used_group quoted_use decoy; do
    printf 'package dep.%s\nfunc value() int { return 1 }\n' "$dependency" > "$work/src/deps/$dependency.s"
done
cat > "$work/src/app/main.s" <<'S'
package app
/* outside /* nested */ import "dep.decoy" */
const quoted = "import \"dep.decoy\""
import ("dep.inline"; "dep.first"); const misleading = "dep.decoy"
import (
    "dep.second"; "dep.aliased" as renamed
)
import named "dep.single"; const another = "dep.decoy"
import dep.bare
import (dep.bare_group; dep.first as first_alias)
use (dep.used_group; "dep.quoted_use")
use "dep.quoted_use"
func main() int { return 0 }
S
S_SOURCE_ROOT="$work" bash "$root/src/cmd/dist/source_closure.sh" src/app/main.s "$work/sources"
for dependency in inline first second aliased single bare bare_group used_group quoted_use; do
    if ! grep -qxF "src/deps/$dependency.s" "$work/sources"; then
        echo "source closure missed dep.$dependency" >&2
        exit 1
    fi
done
if grep -qxF 'src/deps/decoy.s' "$work/sources"; then
    echo 'source closure treated a declaration string as an import' >&2
    exit 1
fi
test "$(wc -l < "$work/sources")" -eq 10
echo 'source closure inline, grouped, semicolon and aliased imports: PASS'
