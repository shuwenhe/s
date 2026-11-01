#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-qualified-variant.XXXXXX)
cat > "$work/qualified.s" <<'EOF'
func main() int {
    fd := 1
    x := pkg_type::Value(fd)
    return 0
}
EOF
if "$root/bin/s_seed" --dump-ast "$work/qualified.s" "$work/qualified.ast" >"$work/seed.log" 2>&1; then
    rg -q 'pkg_type::Value' "$work/qualified.ast"
else
    cat "$work/seed.log" >&2
    exit 1
fi
printf 'qualified variant parser regression: PASS\n'
