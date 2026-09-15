#!/bin/sh
set -eu

root=${S_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
compiler=${1:-"$root/bin/s"}

test -x "$compiler"
export S_PROJECT_ROOT="$root"
export S_SOURCE_ROOT="$root/src"

work=$(mktemp -d "${TMPDIR:-/tmp}/s-generic-function-native.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

src="$work/generic_identity.s"
out="$work/generic_identity"

cat >"$src" <<'SRC'
package main

func identity[T](T x) T {
    return x
}

func main() int {
    x := identity[int](42)
    return x
}
SRC

"$compiler" "$src" -o "$out"

status=0
"$out" >/dev/null 2>&1 || status=$?

if [ "$status" -ne 42 ]; then
    echo "generic-function-native-e2e-check: expected exit code 42, got $status" >&2
    exit 1
fi

printf '%s\n' 'generic-function-native-e2e-check passed'
