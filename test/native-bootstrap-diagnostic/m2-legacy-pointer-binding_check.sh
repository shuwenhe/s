#!/usr/bin/env bash
set -euo pipefail

root=${S_SOURCE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
source="$root/src/cmd/compile/internal/codegen/compiler_integration.s"

if rg -n '\b(lexer|tokens|parser|program|ctx)\*[[:space:]]*:=' "$source"; then
    echo 'M2 legacy pointer binding regression: invalid star-suffixed binding remains' >&2
    exit 1
fi

for name in lexer tokens parser program ctx; do
    grep -Fq "${name}_ptr" "$source"
done

echo 'M2 legacy pointer binding regression: compiler integration bindings use valid names'
