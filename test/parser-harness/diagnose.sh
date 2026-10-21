#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d /tmp/s-parser-harness.XXXXXXXX)
printf 'Parser harness diagnosis artifacts=%s\n' "$work"
cd "$root"
sources=(
    src/cmd/compile/seed/s_seed.c
    src/cmd/compile/seed/bootstrap/bootstrap.c
    src/cmd/compile/seed/lexical/lexer.c
    src/cmd/compile/seed/lexical/selfhost_bridge.c
    src/cmd/compile/seed/error/error.c
    src/cmd/compile/seed/syntax/parser.c
    src/cmd/compile/seed/semantic/analyzer.c
    src/cmd/compile/seed/intermediate/ir.c
    src/cmd/compile/seed/code/generator.c
    src/cmd/compile/seed/code/backend_registry.c
    src/cmd/compile/seed/code/native_backend.c
    src/cmd/compile/seed/code/standalone_amd64_backend.c
    src/cmd/compile/seed/runtime/network_windows.c
    src/cmd/compile/seed/runtime/runtime.c
)
sha256sum "${sources[@]}" test/parser-harness/diagnose.c \
    src/cmd/compile/internal/parser/syntax/lexer.s \
    src/cmd/compile/internal/parser/syntax/parser.s > "$work/input-hashes.txt"
git rev-parse HEAD > "$work/commit.txt"
printf '%q ' "${CC:-cc}" -std=c11 -Wall -Wextra -Werror -DSEED_COMPILE_ONLY \
    test/parser-harness/diagnose.c "${sources[@]}" -o "$work/diagnose" > "$work/command.txt"
printf '\n' >> "$work/command.txt"
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -DSEED_COMPILE_ONLY \
    test/parser-harness/diagnose.c "${sources[@]}" -o "$work/diagnose"
status=0
timeout 30s "$work/diagnose" src/cmd/compile/internal/parser/syntax/lexer.s \
    "$work/lexer.ir" > "$work/diagnosis.txt" 2>&1 || status=$?
printf '%s\n' "$status" > "$work/diagnosis.exit"
cat "$work/diagnosis.txt"
exit "$status"
