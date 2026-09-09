#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

compiler="$root/bin/s"

work=$(mktemp -d)

trap 'rm -rf "$work"' EXIT HUP INT TERM

cd "$work"

cp "$root/test/cli/hello.s" 'hello world.s'

"$compiler" 'hello world.s'

[ "$(./'hello world')" = 'Hello, world!' ]

"$compiler" 'hello world.s' -o 'hello world'

[ "$(./'hello world')" = 'Hello, world!' ]

"$compiler" -o first 'hello world.s'

[ "$(./first)" = 'Hello, world!' ]

"$compiler" build 'hello world.s' -o legacy

[ "$(./legacy)" = 'Hello, world!' ]

"$compiler" 'hello world.s' -o emitted

cmp legacy emitted

"$compiler" --help >help.txt 2>&1

reject() {

    if "$compiler" "$@" >error.txt 2>&1; then

        echo "unexpected success: $*" >&2

        exit 1

    fi

}

reject

reject missing.s

reject 'hello world.s' -o

reject --unknown 'hello world.s' output

reject 'hello world.s' -o 'hello world.s'

cmp "$root/test/cli/hello.s" 'hello world.s'

printf 'invalid source\n' > invalid.s

cp 'hello world' previous

reject invalid.s

cmp 'hello world' previous

printf '%s\n' 'CLI checks passed'
