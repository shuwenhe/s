#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

fail() { printf 'PIPELINE_TOPLEVEL FAIL %s\n' "$1"; exit 1; }
pass() { printf 'PIPELINE_TOPLEVEL PASS %s\n' "$1"; }

tmp=${TMPDIR:-/tmp}/s-pipeline-toplevel.$$
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

pipeline=src/cmd/compile/pipeline/pipeline.s

./bin/s_seed --compile-unit "$tmp/pipeline.ir" "$pipeline" >/dev/null

prepare_line=$(rg -n 'context := pipeline_prepare\(input, output, ssa_margin_override, nostdlib\)' "$pipeline" | cut -d: -f1 || true)
compile_line=$(rg -n 'status := pipeline_compile\(context\)' "$pipeline" | cut -d: -f1 || true)
finish_line=$(rg -n 'result := pipeline_finish\(context, status\)' "$pipeline" | cut -d: -f1 || true)
return_line=$(rg -n 'return result.exit_status' "$pipeline" | cut -d: -f1 || true)

if [ -z "$prepare_line" ] || [ -z "$compile_line" ] || [ -z "$finish_line" ] || [ -z "$return_line" ]; then
    fail "pipeline_build does not expose prepare -> compile -> finish lifecycle"
fi

if [ "$prepare_line" -ge "$compile_line" ] || [ "$compile_line" -ge "$finish_line" ] || [ "$finish_line" -ge "$return_line" ]; then
    fail "pipeline_build lifecycle order is not prepare -> compile -> finish -> return"
fi

if ! rg -q 'func pipeline_compile\(pipeline_context context\) int' "$pipeline" ||
   ! rg -q 'return backend_build\(context.input, context.output, context.ssa_margin_override, context.nostdlib\)' "$pipeline"; then
    fail "pipeline_compile does not preserve backend build execution"
fi

if ! rg -q 'struct pipeline_result' "$pipeline" ||
   ! rg -q 'exit_status: status' "$pipeline"; then
    fail "pipeline_finish does not preserve and summarize backend exit status"
fi

out="$tmp/hello"
./bin/s test/cli/hello.s -o "$out" >/dev/null
"$out" >/dev/null

pass "prepare/compile/finish lifecycle preserves current executable build"
