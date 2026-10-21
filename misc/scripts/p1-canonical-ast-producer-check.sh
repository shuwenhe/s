#!/bin/sh
set -eu

compiler=${1:?usage: p1-canonical-ast-producer-check.sh COMPILER VALID INVALID REPORT}
valid=${2:?usage: p1-canonical-ast-producer-check.sh COMPILER VALID INVALID REPORT}
invalid=${3:?usage: p1-canonical-ast-producer-check.sh COMPILER VALID INVALID REPORT}
report=${4:?usage: p1-canonical-ast-producer-check.sh COMPILER VALID INVALID REPORT}

fail() {
    echo "P1 canonical AST producer: $*" >&2
    exit 1
}

[ -x "$compiler" ] || fail "compiler is not executable: $compiler"
[ -f "$valid" ] || fail "valid fixture is missing: $valid"
[ -f "$invalid" ] || fail "invalid fixture is missing: $invalid"
mkdir -p "$(dirname "$report")"

work=$(mktemp -d "${TMPDIR:-/tmp}/s-p1-authority.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

valid_out="$work/valid.out"
valid_log="$work/valid.log"
invalid_out="$work/invalid.out"
invalid_log="$work/invalid.log"

set +e
"$compiler" --emit-c "$valid" "$valid_out" >"$valid_log" 2>&1
valid_status=$?
"$compiler" --emit-c "$invalid" "$invalid_out" >"$invalid_log" 2>&1
invalid_status=$?
set -e

combined_log="$work/combined.log"
cat "$valid_log" "$invalid_log" >"$combined_log"

fallback=NONE
if grep -Eqi 'bootstrap[-_]subset|fallback|s_seed|stage0' "$combined_log"; then
    fallback=DETECTED
fi

valid_artifact=NO
[ "$valid_status" -eq 0 ] && [ -s "$valid_out" ] && valid_artifact=YES
invalid_rejected=NO
[ "$invalid_status" -ne 0 ] && [ ! -e "$invalid_out" -o ! -s "$invalid_out" ] && invalid_rejected=YES

status=FAIL
first_failure=NONE
if [ "$valid_artifact" != YES ]; then
    first_failure=valid-canonical-production-compile
elif [ "$invalid_rejected" != YES ]; then
    first_failure=invalid-parser-or-semantic-rejection
elif [ "$fallback" != NONE ]; then
    first_failure=hidden-fallback-marker
else
    status=PASS
fi

{
    echo "P1_CANONICAL_AST_PRODUCER=$status"
    echo "compiler=$compiler"
    echo "valid=$valid"
    echo "valid-status=$valid_status"
    echo "valid-artifact=$valid_artifact"
    echo "invalid=$invalid"
    echo "invalid-status=$invalid_status"
    echo "invalid-rejected=$invalid_rejected"
    echo "fallback=$fallback"
    echo "first-failure=$first_failure"
} >"$report"
cat "$report"

[ "$status" = PASS ] || exit 1
