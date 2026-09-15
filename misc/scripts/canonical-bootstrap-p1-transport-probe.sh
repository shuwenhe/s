#!/bin/sh
set -eu

root=${S_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
seed=${SEED_COMPILER_BIN:-"$root/bin/s_seed"}
entry=${CANONICAL_BOOTSTRAP_ENTRY:-"$root/src/cmd/compile/modular_build_main.s"}
report=${CANONICAL_BOOTSTRAP_P1_TRANSPORT_REPORT:-"$root/.bootstrap/modular/canonical-bootstrap-p1-transport-probe.txt"}

mkdir -p "$(dirname -- "$report")"

tmp=${TMPDIR:-/tmp}/canonical-bootstrap-p1-transport.$$
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

before_log="$tmp/before.log"
after_log="$tmp/after.log"
transported="$tmp/modular_build_main.transport.s"
before_ir="$tmp/before.ir"
after_ir="$tmp/after.ir"

awk '
BEGIN { in_import = 0 }
/^[[:space:]]*import[[:space:]]*\([[:space:]]*$/ { in_import = 1; next }
in_import && /^[[:space:]]*\)[[:space:]]*$/ { in_import = 0; next }
in_import {
    line = $0
    sub(/^[[:space:]]*"/, "", line)
    sub(/"[[:space:]]*$/, "", line)
    if (line != "") {
        print "use " line
    }
    next
}
{ print }
' "$entry" >"$transported"

set +e
S_SOURCE_ROOT="$root" "$seed" "$entry" "$before_ir" >"$before_log" 2>&1
before_status=$?
S_SOURCE_ROOT="$root" "$seed" "$transported" "$after_ir" >"$after_log" 2>&1
after_status=$?
set -e

before_first=$(sed -n '1p' "$before_log" | tr '\n' ' ')
after_first=$(sed -n '1p' "$after_log" | tr '\n' ' ')

before_line=0
before_col=0
after_line=0
after_col=0
case "$before_first" in
    *" at "*":"*" "*) before_line=$(printf '%s\n' "$before_first" | sed -n 's/.* at \([0-9][0-9]*\):\([0-9][0-9]*\).*/\1/p'); before_col=$(printf '%s\n' "$before_first" | sed -n 's/.* at \([0-9][0-9]*\):\([0-9][0-9]*\).*/\2/p') ;;
esac
case "$after_first" in
    *" at "*":"*" "*) after_line=$(printf '%s\n' "$after_first" | sed -n 's/.* at \([0-9][0-9]*\):\([0-9][0-9]*\).*/\1/p'); after_col=$(printf '%s\n' "$after_first" | sed -n 's/.* at \([0-9][0-9]*\):\([0-9][0-9]*\).*/\2/p') ;;
esac

before_offset=UNKNOWN
after_offset=UNKNOWN
if [ "$before_line" != 0 ] && [ "$before_col" != 0 ]; then
    before_offset=$(awk -v target_line="$before_line" -v target_col="$before_col" '
        NR < target_line { offset += length($0) + 1 }
        NR == target_line { print offset + target_col; exit }
    ' "$entry")
fi
if [ "$after_line" != 0 ] && [ "$after_col" != 0 ]; then
    after_offset=$(awk -v target_line="$after_line" -v target_col="$after_col" '
        NR < target_line { offset += length($0) + 1 }
        NR == target_line { print offset + target_col; exit }
    ' "$transported")
fi

transport_applied=NO
if ! cmp -s "$entry" "$transported"; then
    transport_applied=YES
fi

compiler_source_modified=NO
if git -C "$root" diff --quiet -- src/cmd/compile/seed src/cmd/compile/stage0 src/cmd/compile/internal src/cmd/compile/modular_build_main.s; then
    compiler_source_modified=NO
else
    compiler_source_modified=YES
fi

bootstrap_subset_expanded=NO
if git -C "$root" diff --quiet -- src/cmd/compile/stage0/bootstrap_subset.c; then
    bootstrap_subset_expanded=NO
else
    bootstrap_subset_expanded=YES
fi

original_blocker_crossed=NO
seed_parser_progressed=NO
if grep -q "near 'compile.internal.semantic'" "$before_log" && ! grep -q "near 'compile.internal.semantic'" "$after_log"; then
    original_blocker_crossed=YES
    seed_parser_progressed=YES
fi

parser_progress_bytes=UNKNOWN
if [ "$before_offset" != UNKNOWN ] && [ "$after_offset" != UNKNOWN ]; then
    parser_progress_bytes=$((after_offset - before_offset))
fi

next_failure_class=UNKNOWN
thin_bridge_status=CONTINUE
probe_verdict=NO_PROGRESS
if [ "$original_blocker_crossed" = YES ]; then
    probe_verdict=PROGRESS
    if grep -Eq 'PARSE_FAIL|expected|got' "$after_log"; then
        next_failure_class=TRANSPORT_GAP
    elif grep -Eq 'SEMANTIC|semantic|undeclared|type|redefinition|arity' "$after_log"; then
        next_failure_class=SEMANTIC_GAP
        thin_bridge_status=STOP
        probe_verdict=STOP_SEMANTIC_GAP
    elif grep -Eq 'LOWER|lower|IR|ir|codegen' "$after_log"; then
        next_failure_class=LOWERING_GAP
        thin_bridge_status=STOP
    elif [ "$after_status" -eq 0 ]; then
        next_failure_class=NONE
    else
        next_failure_class=UNKNOWN
    fi
fi

{
    echo "canonical-bootstrap-p1-transport-probe"
    echo "probe=P1-qualified-package-import"
    echo "compiler-source-modified=$compiler_source_modified"
    echo "bootstrap-subset-expanded=$bootstrap_subset_expanded"
    echo "bridge-parser-authority=NONE"
    echo "bridge-semantic-authority=NONE"
    echo "bridge-mono-authority=NONE"
    echo "bridge-mir-authority=NONE"
    echo "bridge-backend-authority=NONE"
    echo "transport-applied=$transport_applied"
    echo "transport-class=LEXICAL_PACKAGE_IMPORT_NORMALIZATION"
    echo "transport-equivalence-claim=import-string-list-to-use-dotted-path-only"
    echo "before-status=$before_status"
    echo "before-failure-line=$before_line"
    echo "before-failure-column=$before_col"
    echo "before-failure-offset=$before_offset"
    echo "original-first-failure=$before_first"
    echo "after-status=$after_status"
    echo "after-failure-line=$after_line"
    echo "after-failure-column=$after_col"
    echo "after-failure-offset=$after_offset"
    echo "next-failure=$after_first"
    echo "parser-progress-bytes=$parser_progress_bytes"
    echo "seed-parser-progressed=$seed_parser_progressed"
    echo "original-blocker-crossed=$original_blocker_crossed"
    echo "next-failure-class=$next_failure_class"
    echo "thin-bridge-status=$thin_bridge_status"
    echo "probe-verdict=$probe_verdict"
    echo "transported-source=$transported"
    sed 's/^/after-diagnostic=/' "$after_log"
} >"$report"

cat "$report"

case "$probe_verdict" in
    PROGRESS|STOP_SEMANTIC_GAP) exit 0 ;;
    *) exit 1 ;;
esac
