#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
backend="$root/src/cmd/compile/internal/backend_elf64.s"
semantic="$root/src/cmd/compile/internal/semantic.s"
env_source="$root/src/env/env.s"

require_text() {
    local file="$1"
    local pattern="$2"
    local message="$3"
    if ! rg -q "$pattern" "$file"; then
        echo "b6.7.3b declaration identity: missing evidence: $message" >&2
        exit 1
    fi
}

require_text "$env_source" '^package std[.]env$' 'std.env source package identity'
if ! rg -q -F 'func args() string[] {' "$env_source"; then
    echo "b6.7.3b declaration identity: missing evidence: std.env args declaration" >&2
    exit 1
fi
require_text "$backend" 'func append_source_items[(]source_file combined, source_file dep[)]' 'flatten helper'
if ! rg -q -F 'combined.items = append(combined.items, dep.items[i])' "$backend"; then
    echo "b6.7.3b declaration identity: missing evidence: flatten drops dep package side channel" >&2
    exit 1
fi
if ! rg -q -F 'struct function_binding {' "$semantic"; then
    echo "b6.7.3b declaration identity: missing evidence: function binding structure" >&2
    exit 1
fi
require_text "$semantic" 'string name' 'function binding stores declaration name'

if rg -n 'struct function_binding \{' "$semantic" >/dev/null &&
   sed -n '/struct function_binding {/,/}/p' "$semantic" | rg -q 'package_path|string package|declaration_identity'; then
    echo "classification=B6.7.3b_UNEXPECTED_GREEN"
    echo "declaration-identity-preserved=YES"
    exit 0
fi

echo "classification=PACKAGE_IDENTITY_AFTER_FLATTENING_GAP"
echo "source-package-identity=PROVEN path=src/env/env.s package=std.env"
echo "declaration-witness=src/env/env.s:func args"
echo "flattening-site=src/cmd/compile/internal/backend_elf64.s:append_source_items"
echo "flattening-behavior=combined.items+=dep.items[i]"
echo "package-identity-after-flattening=NOT_PROVEN"
echo "semantic-binding-package-path=ABSENT"
echo "required-identity=(std.env,args)"
echo "actual-identity=args"
echo "next=B6.7.3b implement declaration identity preservation before qualified name resolution"
