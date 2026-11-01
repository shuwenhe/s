#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d /tmp/s-parser-capabilities.XXXXXXXX)
printf 'Capability audit artifacts=%s\n' "$work"
cd "$root"
exec 3>"$work/commands.txt"
record() {
    local status=0
    local log=$1
    shift
    printf '%q ' "$@" >&3
    printf '\n' >&3
    "$@" > "$log" 2>&1 || status=$?
    printf '%s\n' "$status" > "$log.exit"
    return "$status"
}
git rev-parse HEAD > "$work/commit.txt"
sha256sum test/parser-harness/fixtures/*.s \
    src/cmd/compile/internal/compiler/frontend.s \
    src/cmd/compile/internal/compiler/native_frontend.s \
    src/cmd/compile/internal/parser/syntax/lexer.s \
    src/cmd/compile/internal/parser/syntax/parser.s > "$work/input-hashes.txt"
printf 'path\tcase\texpected\tcompile\thost_cc\texecute\tobservation\n' > "$work/results.tsv"
cases=(control typed_alloc typed_array_alloc typed_alloc_unknown source_reference reference_literal
    cross_call_mutation box_reference box_mutation box_field_mutation independent_field_borrows
    shared_reference_write assertion_failure)
for path in native hosted-c stage1-c; do
    compiler=${S_HARNESS_COMPILER:-$root/bin/s_compiler}
    if [[ "$path" == stage1-c ]]; then compiler="$root/.bootstrap/native-imports/stage1"; fi
    if [[ ! -x "$compiler" ]]; then
        printf '%s\t-\t-\t-\t-\t-\tUNAVAILABLE\n' "$path" >> "$work/results.tsv"
        continue
    fi
    sha256sum "$compiler" >> "$work/input-hashes.txt"
    for name in "${cases[@]}"; do
        dir="$work/$path/$name"
        mkdir -p "$dir"
        source="$root/test/parser-harness/fixtures/$name.s"
        expected=0
        case "$name" in
            typed_alloc_unknown|reference_literal|shared_reference_write) expected=reject ;;
            assertion_failure) expected=17 ;;
        esac
        compile=0
        cc_status=NA
        execute=NA
        observation=REJECTED
        if [[ "$path" == native ]]; then
            record "$dir/compile.log" timeout 15s "$compiler" build "$source" "$dir/program" || compile=$?
        else
            record "$dir/compile.log" timeout 15s "$compiler" --emit-c "$source" "$dir/program.c" || compile=$?
        fi
        if [[ "$compile" == 0 && "$path" != native ]]; then
            cc_status=0
            record "$dir/cc.log" timeout 20s "${CC:-cc}" -std=c11 -O1 -Wall -Wextra -Werror \
                -DS_COMPILER_CHECK_ALLOCATIONS -I "$root/src/runtime" "$dir/program.c" \
                -o "$dir/program" || cc_status=$?
        fi
        if [[ "$compile" == 0 && ( "$cc_status" == NA || "$cc_status" == 0 ) ]]; then
            execute=0
            record "$dir/execute.log" timeout 5s "$dir/program" || execute=$?
            observation=EXECUTED
        elif [[ "$compile" == 0 ]]; then observation=HOST_CC_FAILED
        fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$path" "$name" "$expected" "$compile" "$cc_status" "$execute" "$observation" >> "$work/results.tsv"
    done
done
cat "$work/results.tsv"
printf 'AUDIT_ONLY: no Parser Harness PASS is inferred from these observations.\n'
