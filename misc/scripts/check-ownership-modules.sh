#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-ownership-modules.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

for module in \
    place_model \
    region_model \
    nll_model \
    drop_model
do
    "$root/bin/s_seed" \
        "$root/src/cmd/compile/internal/ownership/$module.s" \
        "$work/$module.ir"
    if [ ! -s "$work/$module.ir" ]; then
        echo "ownership module check: missing IR for $module" >&2
        exit 1
    fi
done

if ! grep -Fq 'ownership_place_model_verify' "$work/place_model.ir"; then
    echo "ownership module check: place model verifier missing" >&2
    exit 1
fi

if ! grep -Fq 'ownership_region_model_verify' "$work/region_model.ir"; then
    echo "ownership module check: region model verifier missing" >&2
    exit 1
fi

if ! grep -Fq 'ownership_nll_model_verify' "$work/nll_model.ir"; then
    echo "ownership module check: nll model verifier missing" >&2
    exit 1
fi

if ! grep -Fq 'ownership_drop_model_verify' "$work/drop_model.ir"; then
    echo "ownership module check: drop model verifier missing" >&2
    exit 1
fi

misc/scripts/check-mir-nll-ownership.sh

echo "Ownership module contracts check passed"
