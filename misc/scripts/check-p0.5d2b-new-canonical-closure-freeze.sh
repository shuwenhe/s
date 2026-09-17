#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
closure="${STAGE0_CLOSURE:-"$root/.bootstrap/modular/canonical-closure.txt"}"
manifest="${P05D2B_CANONICAL_CLOSURE_MANIFEST:-"$root/.bootstrap/modular/canonical-closure.freeze.manifest"}"
report="${P05D2B_CANONICAL_CLOSURE_FREEZE_REPORT:-"$root/.bootstrap/modular/p0.5d2b-new-canonical-closure-freeze.txt"}"
superseded_hash="${SUPERSEDED_CANONICAL_CLOSURE_HASH:-61bf30372b40e06defa4f8e8aadb6ed240b88e67982c73a3994feea61fe43fa9}"
approval_reason="${CANONICAL_CLOSURE_APPROVAL_REASON:-61bf provenance unrecoverable; current 37-file canonical closure matches HEAD and is frozen with per-file provenance}"

mkdir -p "$(dirname "$manifest")" "$(dirname "$report")"

tmp="${TMPDIR:-/tmp}/s-p05d2b-freeze.$$"
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

bool() {
    if "$@"; then
        echo YES
    else
        echo NO
    fi
}

git_commit=UNKNOWN
if git -C "$root" rev-parse --verify HEAD >/dev/null 2>&1; then
    git_commit=$(git -C "$root" rev-parse HEAD)
fi

dirty_tree=UNKNOWN
dirty_canonical_source=UNKNOWN
dirty_canonical_source_count=0
dirty_canonical_source_files="$tmp/dirty-canonical-source"
: >"$dirty_canonical_source_files"
if git -C "$root" diff --quiet >/dev/null 2>&1 && git -C "$root" diff --cached --quiet >/dev/null 2>&1; then
    dirty_tree=NO
else
    dirty_tree=YES
fi

closure_exists=$(bool test -f "$closure")
closure_count=0
closure_has_entry=NO
aggregate_hash=NONE
missing_count=0
if [ -f "$closure" ]; then
    closure_count=$(wc -l <"$closure" | tr -d ' ')
    closure_has_entry=$(bool grep -qx 'src/cmd/compile/modular_build_main.s' "$closure")
    while IFS= read -r rel; do
        [ -z "$rel" ] && continue
        if [ -f "$root/$rel" ]; then
            shasum -a 256 "$root/$rel" | awk -v rel="$rel" '{ print $1 "  " rel }'
        else
            printf 'MISSING  %s\n' "$rel"
        fi
    done <"$closure" >"$tmp/per-file-sha256"
    missing_count=$(awk '$1 == "MISSING" { n++ } END { print n + 0 }' "$tmp/per-file-sha256")
    aggregate_hash=$(shasum -a 256 "$tmp/per-file-sha256" | awk '{ print $1 }')
    if git -C "$root" rev-parse --verify HEAD >/dev/null 2>&1; then
        while IFS= read -r rel; do
            [ -z "$rel" ] && continue
            if ! git -C "$root" diff --quiet -- "$rel" >/dev/null 2>&1 || \
               ! git -C "$root" diff --cached --quiet -- "$rel" >/dev/null 2>&1; then
                echo "$rel" >>"$dirty_canonical_source_files"
            fi
        done <"$closure"
        dirty_canonical_source_count=$(wc -l <"$dirty_canonical_source_files" | tr -d ' ')
        if [ "$dirty_canonical_source_count" = 0 ]; then
            dirty_canonical_source=NO
        else
            dirty_canonical_source=YES
        fi
    fi
fi

manifest_status=NOT_WRITTEN
if [ "$closure_exists" = YES ] && [ "$closure_has_entry" = YES ] && [ "$missing_count" = 0 ]; then
    {
        echo "P0.5d.2b NEW_CANONICAL_CLOSURE_FREEZE_MANIFEST"
        echo "closure.version=1"
        echo "closure.git-commit=$git_commit"
        echo "closure.hash-algorithm=sha256"
        echo "closure.normalization=raw file bytes; ordered file list as stored in .bootstrap/modular/canonical-closure.txt; per-file lines are '<sha256>  <relative-path>'; aggregate is sha256 of this ordered per-file manifest"
        echo "closure.file-count=$closure_count"
        echo "closure.aggregate-sha256=$aggregate_hash"
        echo "closure.supersedes=$superseded_hash"
        echo "closure.approval-reason=$approval_reason"
        echo "closure.membership-source=$closure"
        echo "closure.entry=src/cmd/compile/modular_build_main.s"
        echo "closure.freeze-role=canonical-stage1-source-binding"
        echo "closure.p0.5c=SSEED_CUT_GREEN_FROZEN"
        echo "closure.p0.5d.1=TRUST_CONTRACT_DEFINED_FROZEN"
        echo "closure.p0.5d.2a=61BF_PROVENANCE_UNRECOVERABLE"
        echo
        echo "[ordered-file-list]"
        sed 's/^/file=/' "$closure"
        echo
        echo "[per-file-sha256]"
        cat "$tmp/per-file-sha256"
    } >"$manifest"
    manifest_status=WRITTEN
fi

manifest_has_version=NO
manifest_has_commit=NO
manifest_has_algorithm=NO
manifest_has_normalization=NO
manifest_has_count=NO
manifest_has_files=NO
manifest_has_per_file=NO
manifest_has_aggregate=NO
manifest_has_reason=NO
manifest_has_supersedes=NO
manifest_aggregate_hash=NONE

if [ -f "$manifest" ]; then
    manifest_has_version=$(bool rg -q '^closure\.version=1$' "$manifest")
    manifest_has_commit=$(bool rg -q '^closure\.git-commit=[0-9a-f]{40}$' "$manifest")
    manifest_has_algorithm=$(bool rg -q '^closure\.hash-algorithm=sha256$' "$manifest")
    manifest_has_normalization=$(bool rg -q '^closure\.normalization=' "$manifest")
    manifest_has_count=$(bool rg -q "^closure\\.file-count=$closure_count$" "$manifest")
    manifest_has_files=$(bool rg -q '^file=src/cmd/compile/modular_build_main\.s$' "$manifest")
    manifest_has_per_file=$(bool rg -q '^[0-9a-f]{64}  src/cmd/compile/modular_build_main\.s$' "$manifest")
    manifest_has_aggregate=$(bool rg -q "^closure\\.aggregate-sha256=$aggregate_hash$" "$manifest")
    manifest_has_reason=$(bool rg -q '^closure\.approval-reason=' "$manifest")
    manifest_has_supersedes=$(bool rg -q "^closure\\.supersedes=$superseded_hash$" "$manifest")
    manifest_aggregate_hash=$(awk -F= '$1 == "closure.aggregate-sha256" { print $2; exit }' "$manifest")
fi

gate=RED
reason=FREEZE_MANIFEST_INCOMPLETE
if [ "$manifest_status" = WRITTEN ] && \
   [ "$dirty_canonical_source" = NO ] && \
   [ "$closure_exists" = YES ] && \
   [ "$closure_has_entry" = YES ] && \
   [ "$missing_count" = 0 ] && \
   [ "$manifest_has_version" = YES ] && \
   [ "$manifest_has_commit" = YES ] && \
   [ "$manifest_has_algorithm" = YES ] && \
   [ "$manifest_has_normalization" = YES ] && \
   [ "$manifest_has_count" = YES ] && \
   [ "$manifest_has_files" = YES ] && \
   [ "$manifest_has_per_file" = YES ] && \
   [ "$manifest_has_aggregate" = YES ] && \
   [ "$manifest_has_reason" = YES ] && \
   [ "$manifest_has_supersedes" = YES ]; then
    gate=GREEN
    reason=NEW_CANONICAL_CLOSURE_FROZEN_WITH_FULL_PROVENANCE
elif [ "$dirty_tree" != NO ]; then
    reason=CANONICAL_SOURCE_DIRTY_REFUSE_FREEZE
fi

{
    echo "P0.5d.2b NEW_CANONICAL_CLOSURE_FREEZE"
    echo "P0_5D_2B_NEW_CANONICAL_CLOSURE_FREEZE=$gate"
    echo
    echo "freeze:"
    echo "  manifest=$manifest"
    echo "  manifest-status=$manifest_status"
    echo "  git-commit=$git_commit"
    echo "  dirty-tree=$dirty_tree"
    echo "  dirty-canonical-source=$dirty_canonical_source"
    echo "  dirty-canonical-source-count=$dirty_canonical_source_count"
    echo "  hash-algorithm=sha256"
    echo "  normalization=raw file bytes; ordered file list; aggregate sha256 over ordered per-file sha256 manifest"
    echo "  file-count=$closure_count"
    echo "  aggregate-sha256=$aggregate_hash"
    echo "  supersedes=$superseded_hash"
    echo "  approval-reason=$approval_reason"
    echo
    echo "closure:"
    echo "  path=$closure"
    echo "  exists=$closure_exists"
    echo "  contains-modular-entry=$closure_has_entry"
    echo "  missing-file-count=$missing_count"
    echo
    echo "manifest-checks:"
    echo "  version=$manifest_has_version"
    echo "  git-commit=$manifest_has_commit"
    echo "  hash-algorithm=$manifest_has_algorithm"
    echo "  normalization=$manifest_has_normalization"
    echo "  file-count=$manifest_has_count"
    echo "  ordered-file-list=$manifest_has_files"
    echo "  per-file-sha256=$manifest_has_per_file"
    echo "  aggregate-sha256=$manifest_has_aggregate"
    echo "  approval-reason=$manifest_has_reason"
    echo "  supersedes=$manifest_has_supersedes"
    echo "  manifest-aggregate-sha256=$manifest_aggregate_hash"
    echo
    echo "SOURCE_BINDING_VERDICT=$reason"
    echo "CANONICAL_CLOSURE_HASH=$aggregate_hash"
    echo
    echo "next:"
    if [ "$gate" = GREEN ]; then
        echo "  source-binding=GREEN"
        echo "  producer-selection=UNBLOCKED_FOR_P0.5d.3"
        echo "  snapshot-generation=STILL_BLOCKED_UNTIL_PRODUCER_SELECTED"
        echo "  snapshot-acceptance=STILL_BLOCKED_UNTIL_SNAPSHOT_EXISTS"
    else
        echo "  source-binding=RED"
        echo "  producer-selection=BLOCKED"
        echo "  snapshot-generation=BLOCKED"
        echo "  snapshot-acceptance=BLOCKED"
    fi
    echo
    echo "DO_NOT_GENERATE_SSEED_IN_P0_5D_2B=YES"
    echo "DO_NOT_MODIFY_SEED=YES"
    echo "DO_NOT_MODIFY_PARSER=YES"
} | tee "$report"

[ "$gate" = GREEN ]
