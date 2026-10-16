#!/usr/bin/env bash
# Evidence collection only. Successful local checks do not prove self-hosting.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
work=$(mktemp -d "$root/.bootstrap/compiler-status.XXXXXX")
report="$work/status.txt"
printf 'EVIDENCE_DIR=%s\n' "$work"
git rev-parse HEAD > "$work/commit.txt"
git status --porcelain=v1 > "$work/worktree.txt"
git diff --binary HEAD > "$work/worktree.patch"
git ls-files --others --exclude-standard > "$work/untracked-files.txt"
sha256sum script/compiler-status-check.sh docs/COMPILER_STATUS.md > "$work/check-definition-hashes.txt"
git ls-files -z src makefile misc script test | xargs -0 sha256sum > "$work/source-hashes.before"
sha256sum "$work/source-hashes.before" > "$work/source-state.sha256"
failed=0
run_check() {
    local name=$1
    shift
    local rc=0
    printf '%q ' "$@" > "$work/$name.command"
    printf '\n' >> "$work/$name.command"
    timeout 60s "$@" > "$work/$name.log" 2>&1 || rc=$?
    printf '%s_EXIT=%s\n' "$name" "$rc" >> "$report"
    if ((rc != 0)); then failed=1; fi
    return "$rc"
}
printf 'COMMIT=%s\nCURRENT_MILESTONE=M1\n' "$(git rev-parse HEAD)" > "$report"
if run_check BUILD make compiler; then
    sha256sum bin/s_seed bin/s_compiler > "$work/artifact-hashes.txt"
    run_check DRIVER_HELP ./bin/s_compiler --help || true
    if run_check HELLO_COMPILE ./bin/s_compiler test/cli/hello.s -o "$work/hello"; then
        run_check HELLO_RUN "$work/hello" || true
        if ! diff -u <(printf 'Hello, world!\n') "$work/HELLO_RUN.log" > "$work/hello-output.diff"; then
            printf 'HELLO_OUTPUT=FAIL\n' >> "$report"
            failed=1
        fi
    else
        printf 'HELLO_RUN=NOT_RUN\n' >> "$report"
    fi
    run_check BACKEND_PARSE ./bin/s_seed --compile-unit "$work/backend.ir" src/cmd/compile/internal/core/backend.s || true
else
    printf 'DRIVER_HELP=NOT_RUN\nHELLO_COMPILE=NOT_RUN\nHELLO_RUN=NOT_RUN\nBACKEND_PARSE=NOT_RUN\n' >> "$report"
fi
run_check CLOSURE python3 script/canonical_closure.py --entry src/cmd/compile/main.s --out-dir "$work/closure" || true
run_check CLOSURE_REGRESSION bash script/test_canonical_closure.sh || true
git ls-files -z src makefile misc script test | xargs -0 sha256sum > "$work/source-hashes.after"
if ! cmp -s "$work/source-hashes.before" "$work/source-hashes.after"; then
    printf 'SOURCE_CHANGED_DURING_CHECK=YES\n' >> "$report"
    failed=1
fi
printf 'CANONICAL_CODEGEN_AUTHORITY=NOT_PROVEN\nSTAGE0_TO_STAGE1=NOT_PROVEN\nSTAGE1_TO_STAGE2_TO_STAGE3=NOT_PROVEN\nSELFHOST=NOT_PROVEN\n' >> "$report"
cat "$report"
exit "$failed"
