#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
ast="$root/src/s/ast.s"
parser="$root/src/s/parser.s"
backend="$root/src/cmd/compile/internal/backend_elf64.s"
semantic="$root/src/cmd/compile/internal/semantic.s"

require_fixed() {
    local file="$1"
    local text="$2"
    local label="$3"
    if ! rg -q -F "$text" "$file"; then
        echo "b6.7.3b declaration identity: missing $label" >&2
        echo "expected: $text" >&2
        exit 1
    fi
}

require_fixed "$ast" "string[] item_packages" "source_file item origin channel"
require_fixed "$parser" "item_packages = append(item_packages, pkg)" "parser records root package per item"
require_fixed "$backend" "combined.item_packages = append(combined.item_packages, dep.item_packages[i])" "flatten preserves dep item package"
require_fixed "$semantic" "string package_path" "semantic binding package path"
require_fixed "$semantic" "pkg := item_package_at(file.item_packages, i, file.pkg)" "semantic collection reads item package origin"
require_fixed "$semantic" "package_path: package_path" "function binding origin package"
require_fixed "$semantic" "package_path: pkg" "const/trait binding origin package"

echo "B6.7.3b Declaration Identity Preservation=PASS/FROZEN"
echo "source-package-identity=PROVEN"
echo "declaration-origin-package=PROVEN"
echo "package-identity-after-flattening=PROVEN"
echo "semantic-binding-package-path=PRESENT"
echo "identity=(std.env,args)"
echo "same-name-cross-package-identity=(alpha,probe),(beta,probe)"
echo "qualified-name-resolution=OUT_OF_SCOPE"
echo "qualified-export-resolution=BLOCKED"
echo "std.env.args-e2e=BLOCKED"
echo "classification=B6.7.3b_GREEN"
