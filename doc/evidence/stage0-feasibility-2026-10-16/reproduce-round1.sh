#!/usr/bin/env bash
set -euo pipefail
cd /home/shuwen/shuwen/s
work=$(mktemp -d /tmp/s-stage0-feasibility.XXXXXX)
printf 'EVIDENCE_DIR=%s\n' "$work"
git rev-parse HEAD > "$work/s-commit.txt"
git -C /home/shuwen/shuwen/go rev-parse HEAD > "$work/go-commit.txt"
git status --porcelain=v1 > "$work/worktree.txt"
gcc --version > "$work/host-cc.txt"
git ls-files -z src makefile | xargs -0 sha256sum > "$work/source-hashes.before"
sources=(src/cmd/compile/seed/s_seed.c src/cmd/compile/seed/bootstrap/bootstrap.c
src/cmd/compile/seed/lexical/lexer.c src/cmd/compile/seed/lexical/selfhost_bridge.c
src/cmd/compile/seed/error/error.c src/cmd/compile/seed/syntax/parser.c
src/cmd/compile/seed/semantic/analyzer.c src/cmd/compile/seed/intermediate/ir.c
src/cmd/compile/seed/code/generator.c src/cmd/compile/seed/code/backend_registry.c
src/cmd/compile/seed/code/native_backend.c src/cmd/compile/seed/code/standalone_amd64_backend.c
src/cmd/compile/seed/runtime/network_windows.c src/cmd/compile/seed/runtime/runtime.c)
printf '%s\n' "${sources[@]}" > "$work/stage0-sources.txt"
printf 'gcc -std=c11 -Wall -Wextra -Werror -o %q ' "$work/stage0" > "$work/stage0-build.command"
printf '%q ' "${sources[@]}" >> "$work/stage0-build.command"
gcc -std=c11 -Wall -Wextra -Werror -o "$work/stage0" "${sources[@]}" > "$work/stage0-build.log" 2>&1
sha256sum "$work/stage0" > "$work/stage0.sha256"
python3 script/canonical_closure.py --entry src/cmd/compile/main.s --out-dir "$work/closure" > "$work/closure.log" 2>&1
mapfile -t closure < "$work/closure/canonical-closure.txt"
printf '%q ' "$work/stage0" --compile-unit "$work/stage1.ir" "${closure[@]}" > "$work/stage1-build.command"
rc=0
timeout 60s "$work/stage0" --compile-unit "$work/stage1.ir" "${closure[@]}" > "$work/stage1-build.log" 2>&1 || rc=$?
printf 'STAGE1_COMPILE_EXIT=%s\n' "$rc"
cat "$work/stage1-build.log"
if ((rc == 0)); then
    S_SOURCE_ROOT="$PWD" timeout 60s "$work/stage0" --emit-bin "$work/stage1.ir" "$work/stage1" > "$work/stage1-emit.log" 2>&1
    sha256sum "$work/stage1" > "$work/stage1.sha256"
    timeout 10s "$work/stage1" --help > "$work/stage1-help.log" 2>&1
else
    printf 'STAGE1_EXECUTABLE=NOT_GENERATED\nSTAGE1_CAPABILITY=NOT_RUN\n'
fi
git ls-files -z src makefile | xargs -0 sha256sum > "$work/source-hashes.after"
cmp "$work/source-hashes.before" "$work/source-hashes.after"
exit "$rc"
