#!/usr/bin/env bash
set -euo pipefail

root="${S_SOURCE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
entry="src/cmd/compile/main.s"
proof_only_entry="src/cmd/compile/compiler_main.s"
report="$root/.bootstrap/bootstrap-authority/b1.1-source-closure-audit.txt"
closure="$root/.bootstrap/bootstrap-authority/b1.1-canonical-source-closure.txt"
tmp="${TMPDIR:-/tmp}/s-b1-source-closure.$$"

mkdir -p "$(dirname "$report")" "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

bool() {
    if "$@"; then
        echo yes
    else
        echo no
    fi
}

line_count() {
    local file=$1
    if [ -f "$file" ]; then
        wc -l <"$file" | tr -d ' '
    else
        echo 0
    fi
}

"$root/src/cmd/dist/source_closure.sh" "$entry" "$tmp/closure.a"
"$root/src/cmd/dist/source_closure.sh" "$entry" "$tmp/closure.b"
cp "$tmp/closure.a" "$closure"

closure_complete=yes
closure_deterministic=$(bool cmp -s "$tmp/closure.a" "$tmp/closure.b")
entry_present=$(bool grep -qxF "$entry" "$closure")
proof_only_present=$(bool grep -qxF "$proof_only_entry" "$closure")
file_count=$(line_count "$closure")

: >"$tmp/missing"
while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if [ ! -f "$root/$rel" ]; then
        echo "$rel" >>"$tmp/missing"
    fi
done <"$closure"
missing_count=$(line_count "$tmp/missing")
if [ "$entry_present" != yes ] || [ "$missing_count" -ne 0 ] || [ "$file_count" -eq 0 ]; then
    closure_complete=no
fi

grep -E '(^|/).*_test[.]s$|/testdata/|(^|/)tests/|^test/' "$closure" >"$tmp/test-sources" || true
test_source_count=$(line_count "$tmp/test-sources")

grep -E '(^|/)seed/|(^|/)legacy/|bootstrap_subset' "$closure" >"$tmp/excluded-source-hits" || true
excluded_source_hit_count=$(line_count "$tmp/excluded-source-hits")

first_unproven="none"
if [ "$entry_present" != yes ]; then
    first_unproven="canonical-entry-missing"
elif [ "$closure_complete" != yes ]; then
    first_unproven="closure-incomplete"
elif [ "$closure_deterministic" != yes ]; then
    first_unproven="closure-nondeterministic"
elif [ "$proof_only_present" = yes ]; then
    first_unproven="proof-only-entry-in-canonical-closure"
elif [ "$excluded_source_hit_count" -ne 0 ]; then
    first_unproven="excluded-source-in-canonical-closure"
elif [ "$test_source_count" -ne 0 ]; then
    first_unproven="test-source-in-canonical-closure"
fi

b11=GREEN
if [ "$first_unproven" != none ]; then
    b11=RED
fi

{
    echo "B1.1 Canonical Compiler Source Closure"
    echo "canonical-compiler-entry=$entry"
    echo "canonical-source-closure=$closure"
    echo "canonical-source-closure-count=$file_count"
    echo "trusted-bootstrap-inputs=src/cmd/dist/source_closure.sh,scripts/s-package-index.tsv"
    echo "excluded-from-canonical-authority=seed/*,legacy/fallback/*,bootstrap_subset*,proof-only implementation,prebuilt compiler artifacts"
    echo "closure-complete=$closure_complete"
    echo "closure-deterministic=$closure_deterministic"
    echo "entry-present=$entry_present"
    echo "proof-only-entry-present=$proof_only_present"
    echo "missing-file-count=$missing_count"
    echo "test-source-count=$test_source_count"
    echo "excluded-source-hit-count=$excluded_source_hit_count"
    echo "first-unproven-boundary=$first_unproven"
    echo "B1.1=$b11"
    echo
    echo "[ordered-source-closure]"
    sed 's/^/file=/' "$closure"
    if [ "$missing_count" -ne 0 ]; then
        echo
        echo "[missing-files]"
        sed 's/^/missing=/' "$tmp/missing"
    fi
    if [ "$test_source_count" -ne 0 ]; then
        echo
        echo "[test-sources-in-closure]"
        sed 's/^/test-source=/' "$tmp/test-sources"
    fi
    if [ "$excluded_source_hit_count" -ne 0 ]; then
        echo
        echo "[excluded-source-hits]"
        sed 's/^/excluded-hit=/' "$tmp/excluded-source-hits"
    fi
} >"$report"

cat "$report"
