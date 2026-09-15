#!/bin/sh
set -eu

root=${S_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
closure=${STAGE0_CLOSURE:-"$root/.bootstrap/modular/canonical-closure.txt"}
stage1=${MODULAR_STAGE1_BIN:-"$root/.bootstrap/modular/s_modular-stage1"}
stage1_c=${MODULAR_STAGE1_C:-"$stage1.c"}
report=${STAGE1_CANONICAL_ENTRY_LINKAGE_REPORT:-"$root/.bootstrap/modular/stage1-canonical-entry-linkage-report.txt"}

mkdir -p "$(dirname -- "$report")"

tmp=${TMPDIR:-/tmp}/stage1-canonical-entry-linkage.$$
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

help_log="$tmp/help.log"
strings_log="$tmp/strings.log"
symbols_log="$tmp/symbols.log"
call_log="$tmp/call.log"

canonical_closure_generated=NO
if [ -f "$closure" ]; then
    canonical_closure_generated=YES
fi

closure_has_entry=NO
if [ -f "$closure" ] && grep -qx 'src/cmd/compile/modular_build_main.s' "$closure"; then
    closure_has_entry=YES
fi

stage1_generated_c=NO
if [ -f "$stage1_c" ]; then
    stage1_generated_c=YES
fi

stage1_binary=NO
if [ -x "$stage1" ]; then
    stage1_binary=YES
fi

canonical_closure_consumed_by_stage1=NO
if [ -f "$stage1_c" ] && rg -q 'closure_files|closure_bytes|closure_funcs' "$stage1_c" && \
   [ "$canonical_closure_generated" = YES ] && [ "$closure_has_entry" = YES ]; then
    canonical_closure_consumed_by_stage1=METADATA_ONLY
fi

canonical_entry_symbol=NO
if [ -x "$stage1" ]; then
    nm "$stage1" >"$symbols_log" 2>/dev/null || true
    if grep -Eq 'modular_build_main|backend_elf64|canonical_build|compile_internal_backend_elf64_build' "$symbols_log"; then
        canonical_entry_symbol=YES
    fi
fi

canonical_entry_linked=NO
if [ -x "$stage1" ]; then
    strings "$stage1" >"$strings_log" 2>/dev/null || true
    if grep -Eq 'compile\.internal\.backend_elf64|modular_build_main|canonical_build' "$strings_log"; then
        canonical_entry_linked=STRING_ONLY
    fi
    if [ "$canonical_entry_symbol" = YES ]; then
        canonical_entry_linked=YES
    fi
fi

set +e
if [ -x "$stage1" ]; then
    "$stage1" --help >"$help_log" 2>&1
    help_status=$?
else
    help_status=127
fi
set -e

canonical_entry_callable=NO
call_probe=NO_KNOWN_CALL_SURFACE
if grep -Eq 'canonical|modular_build_main|backend_elf64' "$help_log"; then
    call_probe=HELP_MENTIONS_CANONICAL_ENTRY_BUT_NO_CALL_COMMAND
fi

bootstrap_subset_build_authority=UNKNOWN
if [ -f "$stage1_c" ] && rg -q 'return bootstrap_subset_build\(argv\[2\], argv\[4\]\)' "$stage1_c"; then
    bootstrap_subset_build_authority=UNCHANGED
fi

missing_capability=NONE
linkage=PROVEN
if [ "$canonical_closure_generated" != YES ]; then
    missing_capability=canonical-closure-generation
    linkage=NOT_PROVEN
elif [ "$closure_has_entry" != YES ]; then
    missing_capability=canonical-entry-not-in-closure
    linkage=NOT_PROVEN
elif [ "$canonical_closure_consumed_by_stage1" != YES ]; then
    missing_capability=stage1-canonical-closure-consumption
    linkage=NOT_PROVEN
elif [ "$canonical_entry_linked" != YES ]; then
    missing_capability=stage1-canonical-entry-linkage
    linkage=NOT_PROVEN
elif [ "$canonical_entry_callable" != YES ]; then
    missing_capability=stage1-canonical-entry-callability
    linkage=NOT_PROVEN
fi

{
    echo "stage1-canonical-entry-linkage-check"
    echo "canonical-closure=$closure"
    echo "stage1-entry=$stage1"
    echo "stage1-generated-c=$stage1_c"
    echo "canonical-closure-generated=$canonical_closure_generated"
    echo "canonical-closure-has-entry=$closure_has_entry"
    echo "stage1-generated-c-present=$stage1_generated_c"
    echo "stage1-binary-present=$stage1_binary"
    echo "canonical-closure-consumed-by-stage1=$canonical_closure_consumed_by_stage1"
    echo "canonical-entry-symbol=$canonical_entry_symbol"
    echo "canonical-entry-linked=$canonical_entry_linked"
    echo "canonical-entry-callable=$canonical_entry_callable"
    echo "canonical-entry-call-probe=$call_probe"
    echo "stage1-help-status=$help_status"
    echo "bootstrap-subset-build-authority=$bootstrap_subset_build_authority"
    echo "missing-capability=$missing_capability"
    if [ -s "$help_log" ]; then
        sed 's/^/stage1-help=/' "$help_log"
    fi
    if [ -s "$symbols_log" ]; then
        grep -E 'modular_build_main|backend_elf64|canonical_build|bootstrap_subset_build' "$symbols_log" | sed 's/^/stage1-symbol=/' || true
    fi
    if [ -s "$strings_log" ]; then
        grep -E 'modular_build_main|compile\.internal\.backend_elf64|canonical_build|bootstrap_subset_build|bootstrap-subset' "$strings_log" | sed 's/^/stage1-string=/' || true
    fi
    if [ -s "$call_log" ]; then
        sed 's/^/call-log=/' "$call_log"
    fi
    echo "stage1-canonical-entry-linkage=$linkage"
} >"$report"

cat "$report"

if [ "$linkage" != PROVEN ]; then
    exit 1
fi
