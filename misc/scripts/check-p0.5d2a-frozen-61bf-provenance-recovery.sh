#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
closure="${STAGE0_CLOSURE:-"$root/.bootstrap/modular/canonical-closure.txt"}"
report="${P05D2A_FROZEN_61BF_PROVENANCE_REPORT:-"$root/.bootstrap/modular/p0.5d2a-frozen-61bf-provenance-recovery.txt"}"
target_hash="${FROZEN_61BF_HASH:-61bf30372b40e06defa4f8e8aadb6ed240b88e67982c73a3994feea61fe43fa9}"

mkdir -p "$(dirname "$report")"

tmp="${TMPDIR:-/tmp}/s-p05d2a-61bf.$$"
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

count_lines() {
    if [ -s "$1" ]; then
        wc -l <"$1" | tr -d ' '
    else
        echo 0
    fi
}

bool_file() {
    [ -f "$1" ] && echo YES || echo NO
}

current_hash=NONE
current_count=0
if [ -f "$closure" ]; then
    current_count=$(wc -l <"$closure" | tr -d ' ')
    while IFS= read -r rel; do
        [ -z "$rel" ] && continue
        if [ -f "$root/$rel" ]; then
            shasum -a 256 "$root/$rel" | awk -v rel="$rel" '{ print $1 "  " rel }'
        else
            printf 'MISSING  %s\n' "$rel"
        fi
    done <"$closure" >"$tmp/current.per-file-sha256"
    current_hash=$(shasum -a 256 "$tmp/current.per-file-sha256" | awk '{ print $1 }')
fi

git_head=UNKNOWN
if git -C "$root" rev-parse --verify HEAD >/dev/null 2>&1; then
    git_head=$(git -C "$root" rev-parse HEAD)
fi

search_paths=(
    ".bootstrap"
    "misc/scripts"
    "makefile"
)

text_hits="$tmp/text-hits"
: >"$text_hits"
for path in "${search_paths[@]}"; do
    if [ -e "$root/$path" ]; then
        rg -n "$target_hash|canonical-closure-hash|closure-hash|closure-files|source-closure|sha256" "$root/$path" 2>/dev/null >>"$text_hits" || true
    fi
done
text_hit_count=$(count_lines "$text_hits")

git_history_hits="$tmp/git-history-hits"
git -C "$root" log --all --date=iso --pretty=format:'COMMIT %H %ad %s' -- \
    .bootstrap misc/scripts makefile 2>/dev/null \
    | rg "COMMIT|$target_hash|canonical-closure-hash|closure-hash|closure-files|source-closure|sha256" \
    >"$git_history_hits" || true
git_history_hit_count=$(count_lines "$git_history_hits")

candidate_reports="$tmp/candidate-reports"
find "$root/.bootstrap" -type f 2>/dev/null | sort | while IFS= read -r file; do
    if rg -q "$target_hash|canonical-closure-hash|source-closure-hash" "$file" 2>/dev/null; then
        printf '%s\n' "$file"
    fi
done >"$candidate_reports"
candidate_report_count=$(count_lines "$candidate_reports")

full_manifest_candidates="$tmp/full-manifest-candidates"
: >"$full_manifest_candidates"
while IFS= read -r file; do
    [ -z "$file" ] && continue
    if rg -q "$target_hash" "$file" 2>/dev/null && \
       rg -q 'per-file|ordered-file|closure\.file|src/cmd/compile/modular_build_main\.s' "$file" 2>/dev/null; then
        printf '%s\n' "$file" >>"$full_manifest_candidates"
    fi
done <"$candidate_reports"
full_manifest_candidate_count=$(count_lines "$full_manifest_candidates")

recovered_commit=NOT_RECOVERED
recovered_files=NOT_RECOVERED
recovered_ordering=NOT_RECOVERED
recovered_normalization=NOT_RECOVERED
recomputed_hash=NOT_RECOVERED
recovery_result=UNRECOVERABLE
recovery_reason=NO_FULL_INPUT_SET_OR_GENERATION_PROCEDURE_FOR_61BF_FOUND

if [ "$full_manifest_candidate_count" -gt 0 ]; then
    recovered_files=POSSIBLE
    recovered_ordering=POSSIBLE
    recovered_normalization=NOT_PROVEN
    recovery_result=PARTIAL_ONLY
    recovery_reason=FOUND_REPORT_REFERENCES_BUT_NOT_FULL_RECOMPUTABLE_PROVENANCE
fi

# Try a bounded historical recomputation over commits that changed the searched
# bootstrap metadata. This does not check out files; it reads blobs from git.
historical_recompute="$tmp/historical-recompute"
: >"$historical_recompute"
if git -C "$root" rev-parse --verify HEAD >/dev/null 2>&1; then
    git -C "$root" log --all --format='%H' -- .bootstrap misc/scripts makefile 2>/dev/null | while IFS= read -r commit; do
        if git -C "$root" cat-file -e "$commit:.bootstrap/modular/canonical-closure.txt" 2>/dev/null; then
            git -C "$root" show "$commit:.bootstrap/modular/canonical-closure.txt" >"$tmp/closure.$commit"
            : >"$tmp/per-file.$commit"
            while IFS= read -r rel; do
                [ -z "$rel" ] && continue
                if git -C "$root" cat-file -e "$commit:$rel" 2>/dev/null; then
                    git -C "$root" show "$commit:$rel" | shasum -a 256 | awk -v rel="$rel" '{ print $1 "  " rel }'
                else
                    printf 'MISSING  %s\n' "$rel"
                fi
            done <"$tmp/closure.$commit" >"$tmp/per-file.$commit"
            hash=$(shasum -a 256 "$tmp/per-file.$commit" | awk '{ print $1 }')
            count=$(wc -l <"$tmp/closure.$commit" | tr -d ' ')
            printf '%s %s %s\n' "$hash" "$count" "$commit" >>"$historical_recompute"
        fi
    done
fi

if rg -q "^$target_hash " "$historical_recompute"; then
    recovered_commit=$(awk -v h="$target_hash" '$1 == h { print $3; exit }' "$historical_recompute")
    recovered_files=YES
    recovered_ordering=YES
    recovered_normalization=GIT_BLOB_BYTES_SHA256_PER_FILE_THEN_SHA256_OF_ORDERED_HASH_LIST
    recomputed_hash="$target_hash"
    recovery_result=RECOVERED
    recovery_reason=HISTORICAL_COMMIT_RECOMPUTES_61BF
fi

explained_obsolete=NO
if [ "$recovery_result" = RECOVERED ] && [ "$current_hash" != "$target_hash" ]; then
    explained_obsolete=YES
    recovery_result=EXPLAINED_BUT_OBSOLETE
    recovery_reason=61BF_REPRODUCED_FROM_HISTORICAL_COMMIT_BUT_CURRENT_CLOSURE_RECOMPUTES_DIFFERENT_HASH
fi

{
    echo "P0.5d.2a FROZEN_61BF_PROVENANCE_RECOVERY"
    echo "P0_5D_2A_FROZEN_61BF_PROVENANCE_RECOVERY=$recovery_result"
    echo
    echo "target:"
    echo "  frozen-hash=$target_hash"
    echo "  current-closure=$closure"
    echo "  current-closure-exists=$(bool_file "$closure")"
    echo "  current-closure-count=$current_count"
    echo "  current-closure-hash=$current_hash"
    echo "  current-git-head=$git_head"
    echo
    echo "searched-locations:"
    for path in "${search_paths[@]}"; do
        echo "  - $path"
    done
    echo "  - git history for .bootstrap misc/scripts makefile"
    echo
    echo "recovery-evidence:"
    echo "  text-hit-count=$text_hit_count"
    echo "  git-history-hit-count=$git_history_hit_count"
    echo "  candidate-report-count=$candidate_report_count"
    echo "  full-manifest-candidate-count=$full_manifest_candidate_count"
    echo "  historical-recompute-count=$(count_lines "$historical_recompute")"
    echo
    echo "recovered-provenance:"
    echo "  files=$recovered_files"
    echo "  ordering=$recovered_ordering"
    echo "  normalization=$recovered_normalization"
    echo "  commit=$recovered_commit"
    echo "  recomputed-hash=$recomputed_hash"
    echo "  explained-obsolete=$explained_obsolete"
    echo
    echo "candidate-reports:"
    if [ "$candidate_report_count" -gt 0 ]; then
        sed "s|$root/||" "$candidate_reports" | sed 's/^/  - /'
    else
        echo "  - NONE"
    fi
    echo
    echo "full-manifest-candidates:"
    if [ "$full_manifest_candidate_count" -gt 0 ]; then
        sed "s|$root/||" "$full_manifest_candidates" | sed 's/^/  - /'
    else
        echo "  - NONE"
    fi
    echo
    echo "historical-recompute-matches:"
    if [ -s "$historical_recompute" ]; then
        rg "^$target_hash |^$current_hash " "$historical_recompute" | sed 's/^/  /' || echo "  - NONE"
    else
        echo "  - NONE"
    fi
    echo
    echo "text-evidence-sample:"
    if [ "$text_hit_count" -gt 0 ]; then
        sed -n '1,100p' "$text_hits" | sed "s|$root/||" | sed 's/^/  /'
    else
        echo "  NONE"
    fi
    echo
    echo "git-history-evidence-sample:"
    if [ "$git_history_hit_count" -gt 0 ]; then
        sed -n '1,120p' "$git_history_hits" | sed 's/^/  /'
    else
        echo "  NONE"
    fi
    echo
    echo "RECOVERY_RESULT=$recovery_result"
    echo "RECOVERY_REASON=$recovery_reason"
    echo
    case "$recovery_result" in
        RECOVERED)
            echo "NEXT=KEEP_61BF_AS_FROZEN_SOURCE_BINDING"
            ;;
        EXPLAINED_BUT_OBSOLETE)
            echo "NEXT=ENTER_FORMAL_REFREEZE_AUDIT_WITH_OLD_AND_CURRENT_INPUT_DIFF"
            ;;
        *)
            echo "NEXT=ENTER_NEW_CANONICAL_CLOSURE_FREEZE_ONLY_AFTER_APPROVAL"
            ;;
    esac
    echo
    echo "blocked-next-steps:"
    echo "  producer-selection=BLOCKED_UNTIL_SOURCE_BINDING_GREEN"
    echo "  snapshot-generation=BLOCKED_UNTIL_SOURCE_BINDING_GREEN"
    echo "  snapshot-acceptance=BLOCKED_UNTIL_SOURCE_BINDING_GREEN"
    echo
    echo "DO_NOT_APPROVE_17DF_IN_P0_5D_2A=YES"
    echo "DO_NOT_GENERATE_SSEED=YES"
    echo "DO_NOT_MODIFY_SEED=YES"
    echo "DO_NOT_MODIFY_PARSER=YES"
} | tee "$report"

[ "$recovery_result" = RECOVERED ] || [ "$recovery_result" = EXPLAINED_BUT_OBSOLETE ]
