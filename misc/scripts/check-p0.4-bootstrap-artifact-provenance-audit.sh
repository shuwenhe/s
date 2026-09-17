#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
workspace_root="${S_WORKSPACE_ROOT:-$(cd "$root/.." && pwd)}"
closure="${STAGE0_CLOSURE:-"$root/.bootstrap/modular/canonical-closure.txt"}"
entry_rel="src/cmd/compile/modular_build_main.s"
report="${P04_BOOTSTRAP_ARTIFACT_PROVENANCE_REPORT:-"$root/.bootstrap/modular/p0.4-bootstrap-artifact-provenance-audit.txt"}"

mkdir -p "$(dirname "$report")"

tmp="${TMPDIR:-/tmp}/s-p0.4-provenance.$$"
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

sha_file() {
    if [ -f "$1" ]; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        echo NONE
    fi
}

bool_file() {
    [ -f "$1" ] && echo YES || echo NO
}

bool_exec() {
    [ -x "$1" ] && echo YES || echo NO
}

count_lines() {
    if [ -s "$1" ]; then
        wc -l <"$1" | tr -d ' '
    else
        echo 0
    fi
}

closure_count=0
canonical_snapshot=NOT_FOUND
canonical_snapshot_hash=NONE
if [ -f "$closure" ]; then
    closure_count=$(wc -l <"$closure" | tr -d ' ')
    if [ "$closure_count" -gt 0 ] && grep -qx "$entry_rel" "$closure"; then
        canonical_snapshot=FOUND
    fi
    while IFS= read -r rel; do
        [ -z "$rel" ] && continue
        if [ -f "$root/$rel" ]; then
            shasum -a 256 "$root/$rel" | awk -v rel="$rel" '{ print $1 "  " rel }'
        else
            printf 'MISSING  %s\n' "$rel"
        fi
    done <"$closure" >"$tmp/closure.hashes"
    canonical_snapshot_hash=$(shasum -a 256 "$tmp/closure.hashes" | awk '{print $1}')
fi

git_commit=UNKNOWN
if git -C "$root" rev-parse --verify HEAD >/dev/null 2>&1; then
    git_commit=$(git -C "$root" rev-parse HEAD)
fi

dirty_tree=UNKNOWN
if git -C "$root" diff --quiet >/dev/null 2>&1 && git -C "$root" diff --cached --quiet >/dev/null 2>&1; then
    dirty_tree=NO
else
    dirty_tree=YES
fi

find "$root" -maxdepth 6 \
    \( -path "$root/.git" -o -path "$root/target" -o -path "$root/node_modules" \) -prune -o \
    -type f \( \
        -name 's_modular-stage1*' -o \
        -name 'bootstrap.ir' -o \
        -name 'stage1.c' -o \
        -name 'stage1.o' -o \
        -name 'stage1.mir' -o \
        -name 'stage1.lowered' -o \
        -path '*/src/cmd/compile/bootstrap/stage1' \
    \) -print | sort >"$tmp/repo-candidates"

find "$workspace_root" -maxdepth 7 \
    \( -path '*/.git' -o -path '*/target' -o -path '*/node_modules' \) -prune -o \
    -type f \( \
        -name 's_modular-stage1*' -o \
        -name 'bootstrap.ir' -o \
        -name 'stage1.c' -o \
        -name 'stage1.o' -o \
        -name 'stage1.mir' -o \
        -name 'stage1.lowered' \
    \) -print 2>/dev/null | sort >"$tmp/workspace-candidates"

find "$root/.bootstrap" -maxdepth 5 -type f 2>/dev/null | sort >"$tmp/bootstrap-files"

git -C "$root" log --all --name-only --pretty=format:'COMMIT %H %ad %s' --date=short -- \
    .bootstrap src/cmd/compile/bootstrap misc/scripts makefile 2>/dev/null \
    | rg 'COMMIT|s_modular-stage1|modular.*stage1|bootstrap\.ir|stage1\.c|stage1\.o|stage1\.mir|stage1\.lowered|canonical.*artifact|provenance|manifest' \
    >"$tmp/git-history-matches" || true

repo_candidate_count=$(count_lines "$tmp/repo-candidates")
workspace_candidate_count=$(count_lines "$tmp/workspace-candidates")
bootstrap_file_count=$(count_lines "$tmp/bootstrap-files")
git_history_match_count=$(count_lines "$tmp/git-history-matches")

legacy_selfhost_stage1="$root/.bootstrap/selfhost/stage1"
legacy_selfhost_stage1_ir="$root/.bootstrap/selfhost/stage1.ir"
legacy_selfhost_manifest="$root/.bootstrap/selfhost/manifest.txt"
legacy_stage1_hash=$(sha_file "$legacy_selfhost_stage1")
legacy_stage1_ir_hash=$(sha_file "$legacy_selfhost_stage1_ir")

legacy_canonical_compatible=NO
legacy_reference_only=NO
if [ -f "$legacy_selfhost_stage1_ir" ]; then
    if rg -q 'modular_build_main|backend_elf64|check_source_file|parse_source' "$legacy_selfhost_stage1_ir" 2>/dev/null; then
        legacy_canonical_compatible=POSSIBLE
    else
        legacy_reference_only=YES
    fi
fi

historical_provenance_status=NONE
if [ "$(bool_file "$legacy_selfhost_manifest")" = YES ]; then
    historical_provenance_status=HISTORICAL_SELFHOST_ONLY
fi

artifact_recovered=NO
candidate_verdict=NO_CANONICAL_STAGE1_ARTIFACT_RECOVERED
if [ "$repo_candidate_count" -gt 0 ] || [ "$workspace_candidate_count" -gt 0 ]; then
    if rg -q 's_modular-stage1|src/cmd/compile/bootstrap/(bootstrap\.ir|stage1\.c|stage1\.o|stage1)$|stage1\.mir|stage1\.lowered' \
        "$tmp/repo-candidates" "$tmp/workspace-candidates" 2>/dev/null; then
        artifact_recovered=POSSIBLE_REQUIRES_MANUAL_VALIDATION
        candidate_verdict=CANDIDATE_PATHS_FOUND_NOT_ACCEPTED_WITHOUT_MANIFEST_AND_STAGE2_STAGE3
    fi
fi

required_manifest_fields="artifact.type target artifact.sha256 source.canonical-closure-hash source.git-commit producer.identity producer.version producer.hash bootstrap-role semantic-authority regeneration.stage1-to-stage2 regeneration.stage2-to-stage3 acceptance.stage2-stage3-equivalence"

provenance_gate=RED
if [ "$artifact_recovered" = YES ]; then
    provenance_gate=GREEN
elif [ "$artifact_recovered" = POSSIBLE_REQUIRES_MANUAL_VALIDATION ]; then
    provenance_gate=YELLOW
fi

{
    echo "P0.4 BOOTSTRAP_ARTIFACT_PROVENANCE_AUDIT"
    echo "P0_4_BOOTSTRAP_ARTIFACT_PROVENANCE=$provenance_gate"
    echo
    echo "source:"
    echo "  canonical-snapshot=$canonical_snapshot"
    echo "  canonical-snapshot-path=$closure"
    echo "  canonical-snapshot-count=$closure_count"
    echo "  canonical-closure-hash=$canonical_snapshot_hash"
    echo "  git-commit=$git_commit"
    echo "  dirty-tree=$dirty_tree"
    echo
    echo "recovery-search:"
    echo "  repository-candidate-count=$repo_candidate_count"
    echo "  workspace-candidate-count=$workspace_candidate_count"
    echo "  bootstrap-file-count=$bootstrap_file_count"
    echo "  git-history-match-count=$git_history_match_count"
    echo "  artifact-recovered=$artifact_recovered"
    echo "  candidate-verdict=$candidate_verdict"
    echo
    echo "repository-candidates:"
    if [ "$repo_candidate_count" -gt 0 ]; then
        sed 's/^/  - /' "$tmp/repo-candidates"
    else
        echo "  - NONE"
    fi
    echo
    echo "workspace-candidates:"
    if [ "$workspace_candidate_count" -gt 0 ]; then
        sed 's/^/  - /' "$tmp/workspace-candidates"
    else
        echo "  - NONE"
    fi
    echo
    echo "legacy-artifacts:"
    echo "  .bootstrap/selfhost/stage1-exists=$(bool_file "$legacy_selfhost_stage1")"
    echo "  .bootstrap/selfhost/stage1-executable=$(bool_exec "$legacy_selfhost_stage1")"
    echo "  .bootstrap/selfhost/stage1-sha256=$legacy_stage1_hash"
    echo "  .bootstrap/selfhost/stage1.ir-exists=$(bool_file "$legacy_selfhost_stage1_ir")"
    echo "  .bootstrap/selfhost/stage1.ir-sha256=$legacy_stage1_ir_hash"
    echo "  .bootstrap/selfhost/manifest-exists=$(bool_file "$legacy_selfhost_manifest")"
    echo "  historical-provenance-status=$historical_provenance_status"
    echo "  canonical-compatible=$legacy_canonical_compatible"
    echo "  reference-only=$legacy_reference_only"
    echo "  verdict=REFERENCE_ONLY_NOT_ACCEPTED_AS_CANONICAL_STAGE1"
    echo
    echo "git-history-evidence:"
    if [ "$git_history_match_count" -gt 0 ]; then
        sed -n '1,80p' "$tmp/git-history-matches" | sed 's/^/  /'
        if [ "$git_history_match_count" -gt 80 ]; then
            echo "  ... truncated in report: $git_history_match_count matching lines"
        fi
    else
        echo "  NONE"
    fi
    echo
    echo "accepted-artifact-manifest-contract:"
    for field in $required_manifest_fields; do
        echo "  required-field=$field"
    done
    echo
    echo "bootstrap-creation-vs-regeneration:"
    echo "  bootstrap-creation=EXTERNAL_OR_RECOVERED_ARTIFACT_ALLOWED_WITH_PROVENANCE"
    echo "  steady-state-regeneration=Stage1 -> Stage2 -> Stage3 REQUIRED"
    echo "  semantic-authority=canonical-source"
    echo "  binary-authority=bootstrap-trust-root-only"
    echo
    echo "next-gates:"
    echo "  P0.5_STAGE1_TO_STAGE2_REGENERATION=BLOCKED_UNTIL_P0.4_ARTIFACT"
    echo "  P0.6_STAGE2_STAGE3_CONVERGENCE=BLOCKED_UNTIL_P0.5"
    echo
    echo "ROOT_BLOCKER=NO_RECOVERED_OR_PROVENANCED_CANONICAL_STAGE1_ARTIFACT"
    echo "NO_CHECKED_CANONICAL_STAGE1_ARTIFACT_AT_ANY_EXECUTABLE_LEVEL=YES"
    echo "DO_NOT_FIX_ABIUTILS_144=YES"
    echo "DO_NOT_FIX_HISTORICAL_IS_ERR=YES"
    echo "DO_NOT_IMPLEMENT_THIRD_COMPILER=YES"
} | tee "$report"

[ "$provenance_gate" = GREEN ]
