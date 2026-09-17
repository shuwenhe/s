#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
closure="${STAGE0_CLOSURE:-"$root/.bootstrap/modular/canonical-closure.txt"}"
report="${P05D2_CANONICAL_CLOSURE_DRIFT_REPORT:-"$root/.bootstrap/modular/p0.5d2-canonical-closure-drift-audit.txt"}"
closure_freeze_manifest="${CANONICAL_CLOSURE_FREEZE_MANIFEST:-"$root/.bootstrap/modular/canonical-closure.freeze.manifest"}"
expected_closure_hash="${CANONICAL_CLOSURE_HASH:-}"
if [ -z "$expected_closure_hash" ] && [ -f "$closure_freeze_manifest" ]; then
    expected_closure_hash=$(awk -F= '$1 == "closure.aggregate-sha256" { print $2; exit }' "$closure_freeze_manifest")
fi
expected_closure_hash="${expected_closure_hash:-61bf30372b40e06defa4f8e8aadb6ed240b88e67982c73a3994feea61fe43fa9}"

mkdir -p "$(dirname "$report")"

tmp="${TMPDIR:-/tmp}/s-p05d2-drift.$$"
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

sha_file() {
    if [ -f "$1" ]; then
        shasum -a 256 "$1" | awk '{ print $1 }'
    else
        echo NONE
    fi
}

closure_exists=$(bool test -f "$closure")
closure_count=0
closure_has_entry=NO
current_closure_hash=NONE
hash_algorithm_available=YES
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
    done <"$closure" >"$tmp/current.hashes"
    current_closure_hash=$(shasum -a 256 "$tmp/current.hashes" | awk '{ print $1 }')
else
    : >"$tmp/current.hashes"
fi

git_commit=UNKNOWN
if git -C "$root" rev-parse --verify HEAD >/dev/null 2>&1; then
    git_commit=$(git -C "$root" rev-parse HEAD)
fi

tracked_modified_count=0
tracked_modified_files="$tmp/tracked-modified"
: >"$tracked_modified_files"
if git -C "$root" rev-parse --verify HEAD >/dev/null 2>&1 && [ -f "$closure" ]; then
    while IFS= read -r rel; do
        [ -z "$rel" ] && continue
        if ! git -C "$root" diff --quiet -- "$rel" >/dev/null 2>&1 || \
           ! git -C "$root" diff --cached --quiet -- "$rel" >/dev/null 2>&1; then
            echo "$rel" >>"$tracked_modified_files"
        fi
    done <"$closure"
    tracked_modified_count=$(wc -l <"$tracked_modified_files" | tr -d ' ')
fi

closure_file_modified=NO
if ! git -C "$root" diff --quiet -- "${closure#"$root/"}" >/dev/null 2>&1 || \
   ! git -C "$root" diff --cached --quiet -- "${closure#"$root/"}" >/dev/null 2>&1; then
    closure_file_modified=YES
fi

membership_changed=NOT_PROVEN
head_closure_count=UNKNOWN
head_closure_hash=NONE
head_hash_using_current_membership=NONE
head_membership_diff=UNKNOWN
if git -C "$root" cat-file -e "HEAD:${closure#"$root/"}" 2>/dev/null; then
    git -C "$root" show "HEAD:${closure#"$root/"}" >"$tmp/head-closure"
    head_closure_count=$(wc -l <"$tmp/head-closure" | tr -d ' ')
    if cmp -s "$closure" "$tmp/head-closure"; then
        membership_changed=NO
        head_membership_diff=NO
    else
        membership_changed=YES
        head_membership_diff=YES
        diff -u "$tmp/head-closure" "$closure" >"$tmp/membership.diff" || true
    fi
    while IFS= read -r rel; do
        [ -z "$rel" ] && continue
        if git -C "$root" cat-file -e "HEAD:$rel" 2>/dev/null; then
            git -C "$root" show "HEAD:$rel" | shasum -a 256 | awk -v rel="$rel" '{ print $1 "  " rel }'
        else
            printf 'MISSING  %s\n' "$rel"
        fi
    done <"$tmp/head-closure" >"$tmp/head.hashes"
    head_closure_hash=$(shasum -a 256 "$tmp/head.hashes" | awk '{ print $1 }')
fi

if git -C "$root" rev-parse --verify HEAD >/dev/null 2>&1 && [ -f "$closure" ]; then
    while IFS= read -r rel; do
        [ -z "$rel" ] && continue
        if git -C "$root" cat-file -e "HEAD:$rel" 2>/dev/null; then
            git -C "$root" show "HEAD:$rel" | shasum -a 256 | awk -v rel="$rel" '{ print $1 "  " rel }'
        else
            printf 'MISSING  %s\n' "$rel"
        fi
    done <"$closure" >"$tmp/head-current-membership.hashes"
    head_hash_using_current_membership=$(shasum -a 256 "$tmp/head-current-membership.hashes" | awk '{ print $1 }')
fi

current_matches_head=NO
if [ "$current_closure_hash" = "$head_closure_hash" ] && [ "$current_closure_hash" != NONE ]; then
    current_matches_head=YES
elif [ "$current_closure_hash" = "$head_hash_using_current_membership" ] && [ "$current_closure_hash" != NONE ]; then
    current_matches_head=YES
fi

hash_occurrences="$tmp/hash-occurrences"
rg -n "$expected_closure_hash|$current_closure_hash" "$root/.bootstrap" "$root/misc/scripts" \
    --glob '!p0.5d2-canonical-closure-drift-audit.txt' \
    --glob '!check-p0.5d2-canonical-closure-drift-audit.sh' \
    2>/dev/null >"$hash_occurrences" || true
hash_occurrence_count=$(wc -l <"$hash_occurrences" | tr -d ' ')

old_report_hashes="$tmp/report-hashes"
rg -n 'canonical-closure-hash=|source-closure-hash=|hash=' "$root/.bootstrap/modular" \
    --glob '!p0.5d2-canonical-closure-drift-audit.txt' \
    2>/dev/null >"$old_report_hashes" || true

hash_algorithm_changed=NO
if ! rg -q 'shasum -a 256.*closure.hashes|shasum -a 256.*tmp_hashes|canonical_snapshot_hash=.*shasum -a 256' "$root/misc/scripts" 2>/dev/null; then
    hash_algorithm_changed=NOT_PROVEN
fi

canonical_source_changed=NOT_PROVEN
if [ "$tracked_modified_count" -gt 0 ]; then
    canonical_source_changed=YES_WORKTREE_DIRTY
elif [ "$current_matches_head" = YES ]; then
    canonical_source_changed=NO_RELATIVE_TO_HEAD_BUT_UNKNOWN_RELATIVE_TO_FROZEN_61BF
fi

classification=NOT_PROVEN
verdict=INVESTIGATE
gate=RED
if [ "$current_closure_hash" = "$expected_closure_hash" ]; then
    classification=NO_DRIFT
    verdict=SOURCE_BINDING_GREEN
    gate=GREEN
elif [ "$hash_algorithm_changed" = NOT_PROVEN ]; then
    classification=HASH_PROCEDURE_DRIFT_NOT_PROVEN
    verdict=FIX_HASH_PROCEDURE_OR_RECORD_PROCEDURE
elif [ "$membership_changed" = YES ]; then
    classification=CLOSURE_MEMBERSHIP_CHANGED_RELATIVE_TO_HEAD
    verdict=RESTORE_FROZEN_CLOSURE_OR_APPROVE_NEW_FROZEN_CLOSURE
elif [ "$tracked_modified_count" -gt 0 ]; then
    classification=CANONICAL_SOURCE_CHANGED_IN_WORKTREE
    verdict=RESTORE_FROZEN_CLOSURE_OR_APPROVE_NEW_FROZEN_CLOSURE
elif [ "$current_matches_head" = YES ]; then
    classification=FROZEN_HASH_PROVENANCE_MISSING_CURRENT_HEAD_REPRODUCES_17DF_NOT_61BF
    verdict=INVESTIGATE_OR_APPROVE_NEW_FROZEN_CLOSURE_WITH_PROVENANCE
fi

{
    echo "P0.5d.2 CANONICAL_CLOSURE_DRIFT_AUDIT"
    echo "P0_5D_2_SOURCE_BINDING=$gate"
    echo
    echo "FROZEN_CLOSURE_HASH=$expected_closure_hash"
    echo "CURRENT_CLOSURE_HASH=$current_closure_hash"
    echo "HEAD_CLOSURE_HASH=$head_closure_hash"
    echo "HEAD_HASH_USING_CURRENT_MEMBERSHIP=$head_hash_using_current_membership"
    echo "FREEZE_MANIFEST=$closure_freeze_manifest"
    echo
    echo "hash-status:"
    echo "  source-binding-status=$( [ "$current_closure_hash" = "$expected_closure_hash" ] && echo MATCH || echo MISMATCH )"
    echo "  current-matches-head=$current_matches_head"
    echo "  hash-algorithm-changed=$hash_algorithm_changed"
    echo "  closure-membership-changed=$membership_changed"
    echo "  canonical-source-changed=$canonical_source_changed"
    echo
    echo "closure:"
    echo "  path=$closure"
    echo "  exists=$closure_exists"
    echo "  count=$closure_count"
    echo "  contains-modular-entry=$closure_has_entry"
    echo "  closure-file-modified=$closure_file_modified"
    echo "  head-closure-count=$head_closure_count"
    echo "  head-membership-diff=$head_membership_diff"
    echo
    echo "git:"
    echo "  head=$git_commit"
    echo "  tracked-canonical-source-modified-count=$tracked_modified_count"
    echo "  tracked-canonical-source-modified-files:"
    if [ "$tracked_modified_count" -gt 0 ]; then
        sed 's/^/    - /' "$tracked_modified_files"
    else
        echo "    - NONE"
    fi
    echo
    echo "hash-provenance:"
    echo "  matching-hash-occurrence-count=$hash_occurrence_count"
    if [ "$hash_occurrence_count" -gt 0 ]; then
        sed -n '1,80p' "$hash_occurrences" | sed "s|$root/||" | sed 's/^/    /'
    else
        echo "    NONE"
    fi
    echo
    echo "known-report-hashes:"
    sed -n '1,120p' "$old_report_hashes" | sed "s|$root/||" | sed 's/^/    /'
    echo
    echo "membership-diff:"
    if [ -f "$tmp/membership.diff" ]; then
        sed -n '1,120p' "$tmp/membership.diff" | sed 's/^/    /'
    else
        echo "    - NONE"
    fi
    echo
    echo "change-classification=$classification"
    echo "SOURCE_BINDING_VERDICT=$verdict"
    echo
    echo "blocked-next-steps:"
    if [ "$gate" = GREEN ]; then
        echo "  producer-selection=UNBLOCKED_FOR_P0.5d.3"
        echo "  snapshot-generation=STILL_BLOCKED_UNTIL_PRODUCER_SELECTED"
        echo "  snapshot-acceptance=STILL_BLOCKED_UNTIL_SNAPSHOT_EXISTS"
    else
        echo "  producer-selection=BLOCKED_UNTIL_SOURCE_BINDING_GREEN"
        echo "  snapshot-generation=BLOCKED_UNTIL_SOURCE_BINDING_GREEN"
        echo "  snapshot-acceptance=BLOCKED_UNTIL_SOURCE_BINDING_GREEN"
    fi
    echo
    echo "DO_NOT_UPDATE_EXPECTED_HASH_WITHOUT_APPROVAL=YES"
    echo "DO_NOT_GENERATE_SSEED=YES"
    echo "DO_NOT_MODIFY_SEED=YES"
    echo "DO_NOT_MODIFY_PARSER=YES"
} | tee "$report"

[ "$gate" = GREEN ]
