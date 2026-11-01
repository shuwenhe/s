#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-p1-authority.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

cat >"$work/fake-compiler" <<'EOF'
#!/bin/sh
echo 'bootstrap-subset: fake fallback'
exit 0
EOF
chmod +x "$work/fake-compiler"

if "$root/misc/scripts/p1-canonical-ast-producer-check.sh" \
    "$work/fake-compiler" "$root/test/selfhost/p1_canonical_ast_producer_valid.s" \
    "$root/test/selfhost/p1_canonical_ast_producer_invalid.s" "$work/report" >"$work/out" 2>&1; then
    echo 'expected fallback marker to fail P1' >&2
    exit 1
fi
grep -q 'fallback' "$work/out"

echo 'P1 canonical AST producer RED: fallback marker rejected'
