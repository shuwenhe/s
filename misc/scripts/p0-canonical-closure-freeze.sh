#!/bin/sh
set -eu

root=${1:-$(pwd)}
closure=${2:-$root/.bootstrap/modular/canonical-closure.txt}
out_dir=${3:-$root/.bootstrap/modular}
manifest=${4:-$out_dir/canonical-closure.freeze.manifest}
report=${5:-$out_dir/p0-canonical-closure-freeze-report.txt}

fail() {
    echo "P0 canonical closure: $*" >&2
    exit 1
}

[ -d "$root" ] || fail "repository root does not exist: $root"
[ -f "$closure" ] || fail "closure does not exist: $closure"
mkdir -p "$out_dir"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/s-p0-freeze.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

count=0
while IFS= read -r rel || [ -n "$rel" ]; do
    [ -n "$rel" ] || continue
    case "$rel" in
        /*|../*|*/../*|./*|*/./*) fail "path is not repository-relative: $rel" ;;
        src/cmd/compile/seed/*|src/cmd/compile/stage0/*|*/bootstrap_subset*|*legacy*)
            fail "forbidden bootstrap authority path: $rel" ;;
    esac
    case "\n$(cat "$tmp/paths" 2>/dev/null || true)\n" in
        *"\n$rel\n"*) fail "duplicate closure entry: $rel" ;;
    esac
    printf '%s\n' "$rel" >>"$tmp/paths"
    [ -f "$root/$rel" ] || fail "listed source is missing: $rel"
    sha256sum "$root/$rel" | awk -v p="$rel" '{print $1 "  " p}' >>"$tmp/hashes"
    count=$((count + 1))
done <"$closure"

[ "$count" -gt 0 ] || fail "closure is empty"

closure_hash=$(sha256sum "$tmp/hashes" | awk '{print $1}')
manifest_tmp="$manifest.tmp.$$"
{
    echo 's-canonical-closure-freeze-v1'
    echo "repository-root=$root"
    echo "closure=$closure"
    echo "closure-count=$count"
    echo "closure-sha256=$closure_hash"
    echo 'stage0-role=allowed-only-as-initial-artifact-producer'
    echo 'production-authority=canonical-s-parser'
    echo 'fallback-policy=forbidden'
    echo 'files-sha256-begin'
    sort "$tmp/hashes"
    echo 'files-sha256-end'
} >"$manifest_tmp"
mv "$manifest_tmp" "$manifest"

manifest_hash=$(sha256sum "$manifest" | awk '{print $1}')
{
    echo 'P0_CANONICAL_CLOSURE=PASS'
    echo "closure=$closure"
    echo "closure-count=$count"
    echo "closure-sha256=$closure_hash"
    echo "manifest=$manifest"
    echo "manifest-sha256=$manifest_hash"
    echo 'fallback-policy=FORBIDDEN'
} >"$report"
cat "$report"
