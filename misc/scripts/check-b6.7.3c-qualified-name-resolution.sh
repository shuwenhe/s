#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
semantic="$root/src/cmd/compile/internal/semantic.s"

require_fixed() {
    local file="$1"
    local text="$2"
    local label="$3"
    if ! rg -q -F "$text" "$file"; then
        echo "b6.7.3c qualified name resolution: missing $label" >&2
        echo "expected: $text" >&2
        exit 1
    fi
}

require_fixed "$semantic" "string package_path" "B6.7.3b declaration package identity"
require_fixed "$semantic" "package_path: package_path" "function binding package origin"

if ! rg -q -F "func lookup_qualified_functions(function_binding[] functions, string package_path, string name) function_binding[]" "$semantic"; then
    echo "classification=QUALIFIED_NAME_RESOLUTION_GAP" >&2
    echo "declaration-identity=PROVEN" >&2
    echo "resolver-consumes-package-path=NO" >&2
    echo "required-lookup=(package_path,name)" >&2
    echo "qualified-name-resolution=NOT_IMPLEMENTED" >&2
    exit 1
fi

require_fixed "$semantic" "qualified_expr_path(value.callee.value)" "callee member chain projection"
require_fixed "$semantic" "lookup_qualified_functions(functions, qualified_package, qualified_name)" "qualified function binding lookup"

if rg -q -F 'package_path == "std.env"' "$semantic" || rg -q -F 'name == "args"' "$semantic"; then
    echo "classification=QUALIFIED_NAME_SPECIAL_CASE_LEAK" >&2
    echo "std-special-case=FORBIDDEN" >&2
    exit 1
fi

echo "B6.7.3c Qualified Name Resolution=PASS/FROZEN"
echo "declaration-identity=PROVEN"
echo "resolver-consumes-package-path=PROVEN"
echo "qualified-lookup-key=(package_path,name)"
echo "std-special-case=NO"
echo "identity-rework=NO"
echo "qualified-name-resolution=B6.7.3c"
echo "qualified-call-e2e=NOT_CLAIMED"
echo "classification=B6.7.3c_GREEN"
