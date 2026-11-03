#!/usr/bin/env bash
# Dependencies are installed by the workflow; this entrypoint never uses sudo.
# Usage: ci-core.sh EXACT_COMMIT NEW_OUTPUT_DIR [core|full]
set -euo pipefail
revision=${1:?exact commit required}
output=${2:?fresh output directory required}
mode=${3:-core}
if [[ -e "$output" || -L "$output" || -e "$output.tests.stdout.log" || -e "$output.tests.stderr.log" ]]; then
    echo 'ci-core: choose a fresh output directory; existing evidence is preserved' >&2
    exit 2
fi
if [[ ! "$revision" =~ ^[0-9a-f]{40}$ ]] || [[ "$mode" != core && "$mode" != full ]]; then
    echo 'ci-core: exact 40-character commit and core/full mode required' >&2
    exit 2
fi
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
mkdir -p "$(dirname "$output")"
set -C
python3 -m unittest discover -s "$root/test/bootstrap-reproducibility" -v \
    > "$output.tests.stdout.log" 2> "$output.tests.stderr.log"
cat "$output.tests.stderr.log"
python3 -u "$root/misc/scripts/cleanroom-selfhost.py" \
    --repository "$root" --revision "$revision" --output "$output" --mode "$mode"
