#!/bin/sh
set -eu

root=${S_SOURCE_ROOT:-$(pwd)}
entry=${1:?usage: stage0_closure_check.sh ENTRY CLOSURE}
closure=${2:?usage: stage0_closure_check.sh ENTRY CLOSURE}

if [ ! -s "$closure" ]; then
    echo "stage0 closure check: missing or empty closure: $closure" >&2
    exit 1
fi

if ! grep -qxF "$entry" "$closure"; then
    echo "stage0 closure check: entry missing from closure: $entry" >&2
    exit 1
fi

closure_count=$(wc -l <"$closure" | tr -d ' ')
if [ "$closure_count" -lt 2 ]; then
    echo "stage0 closure check: canonical compiler closure did not expand beyond entry" >&2
    exit 1
fi

if grep -Eq '(^|/).*_test[.]s$|/testdata/|^test/' "$closure"; then
    echo "stage0 closure check: closure includes test-only sources" >&2
    grep -En '(^|/).*_test[.]s$|/testdata/|^test/' "$closure" >&2
    exit 1
fi

missing=0
while IFS= read -r source_file; do
    [ -n "$source_file" ] || continue
    if [ ! -f "$root/$source_file" ]; then
        echo "stage0 closure check: listed source not found: $source_file" >&2
        missing=1
    fi
done <"$closure"

if [ "$missing" -ne 0 ]; then
    exit 1
fi

echo "stage0 closure check passed: $closure_count files"
