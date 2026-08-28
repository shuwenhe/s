#!/bin/sh
set -eu

dir=${1:?usage: audit.sh BOOTSTRAP_DIR COMPILER}
compiler=${2:?usage: audit.sh BOOTSTRAP_DIR COMPILER}
manifest="$dir/manifest.txt"

test -s "$dir/stage2.ir"
test -s "$dir/stage3.ir"
cmp "$dir/stage2.ir" "$dir/stage3.ir"

printf 'bootstrap convergence\n'
printf '  stage2.ir == stage3.ir: yes\n'
printf '  compiler artifact: %s\n' "$compiler"
if readelf -lW "$compiler" 2>/dev/null | grep -q '[[:space:]]INTERP[[:space:]]'; then
    printf '  provenance: seed-hosted (dynamic interpreter present)\n'
else
    printf '  provenance: static candidate (run true-selfhost-check for full verification)\n'
fi

printf 'dependency audit\n'
if nm -a "$compiler" 2>/dev/null | grep -Eq 'seed_(compile|bootstrap)|runtime_execute_text|emit_native_from_ir_file'; then
    printf '  seed dependency: present\n'
else
    printf '  seed dependency: absent\n'
fi

if [ -f "$manifest" ]; then
    printf 'manifest\n'
    printf '  path: %s\n' "$manifest"
    sed -n '1,9p' "$manifest"
fi
