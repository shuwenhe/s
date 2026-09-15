#!/bin/sh
set -eu

root=${S_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
stage0=${STAGE0_BIN:-"$root/.bootstrap/modular/s_stage0"}
closure=${STAGE0_CLOSURE:-"$root/.bootstrap/modular/canonical-closure.txt"}
stage1=${MODULAR_STAGE1_BIN:-"$root/.bootstrap/modular/s_modular-stage1"}
report=${CANONICAL_SOURCE_COMPILATION_REPORT:-"$root/.bootstrap/modular/canonical-source-compilation-report.txt"}
bootstrap_report=${MODULAR_BOOTSTRAP_REPORT:-"$root/.bootstrap/modular/bootstrap-report.txt"}

mkdir -p "$(dirname -- "$report")"

verdict=PASS
blocker=""

record_fail() {
    if [ "$verdict" = PASS ]; then
        verdict=FAIL
        blocker=$1
    fi
}

contains_file_line() {
    file=$1
    needle=$2
    test -f "$file" && grep -qx "$needle" "$file"
}

contains_text() {
    file=$1
    needle=$2
    test -f "$file" && grep -q "$needle" "$file"
}

tmp=${TMPDIR:-/tmp}/canonical-source-probe.$$
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

probe="$tmp/canonical_probe.s"
probe_out="$tmp/canonical_probe"
probe_log="$tmp/canonical_probe.log"

cat >"$probe" <<'SRC'
package cmd
import ()
func main() int {
    return 7
}
SRC

stage0_status=FAIL
if [ -x "$stage0" ]; then
    stage0_status=PASS
else
    record_fail "stage0-missing-or-not-executable"
fi

stage0_identity=FAIL
if contains_text "$bootstrap_report" "producer=$stage0" &&
   contains_text "$bootstrap_report" "role=explicit-c-stage0"; then
    stage0_identity=PASS
else
    record_fail "stage0-identity-not-proven"
fi

closure_status=FAIL
if [ -s "$closure" ] &&
   contains_file_line "$closure" "src/cmd/compile/modular_build_main.s"; then
    closure_status=PASS
else
    record_fail "canonical-closure-missing-modular-entry"
fi

stage1_status=FAIL
if [ -x "$stage1" ] &&
   contains_text "$bootstrap_report" "emitted $stage1" &&
   contains_text "$bootstrap_report" "stage0: consumed"; then
    stage1_status=PASS
else
    record_fail "stage1-provenance-not-established"
fi

embedded_marker=NO
delegation_status=PASS
delegation_markers="$tmp/delegation_markers.txt"
strings "$stage1" 2>/dev/null | grep -E 'bin/s_seed|s_seed --emit|bootstrap-subset|artifact-only: canonical-source-compilation=NOT_PROVEN' >"$delegation_markers" || true
if [ -s "$delegation_markers" ]; then
    embedded_marker=YES
fi

probe_status=FAIL
probe_exit=NOT_RUN
if [ -x "$stage1" ]; then
    set +e
    S_PROJECT_ROOT="$root" S_SOURCE_ROOT="$root/src" "$stage1" build "$probe" -o "$probe_out" >"$probe_log" 2>&1
    build_status=$?
    set -e
    if [ "$build_status" -eq 0 ] && [ -x "$probe_out" ]; then
        set +e
        "$probe_out" >/dev/null 2>&1
        probe_exit=$?
        set -e
        if [ "$probe_exit" -eq 7 ]; then
            probe_status=PASS
        else
            record_fail "canonical-syntax-probe-exit-mismatch"
        fi
    else
        if grep -q 'bootstrap-subset:' "$probe_log"; then
            record_fail "canonical-syntax-probe-hit-bootstrap-subset"
        else
            record_fail "canonical-syntax-probe-build-failed"
        fi
    fi
fi

runtime_delegation=NO
semantic_delegation=NO
if [ -s "$probe_log" ] && grep -Eq 'bootstrap-subset:|bin/s_seed|s_seed --emit' "$probe_log"; then
    runtime_delegation=YES
    delegation_status=FAIL
    record_fail "runtime-delegation-observed"
fi
if [ -s "$probe_log" ] && grep -Eq 'fallback|delegate|delegat|bootstrap-subset:|s_seed' "$probe_log"; then
    semantic_delegation=YES
    delegation_status=FAIL
    record_fail "semantic-delegation-observed"
fi

{
    echo "canonical-source-compilation-check"
    echo "stage0-identity=$stage0_status"
    echo "stage0-authority=$stage0_identity"
    echo "closure-authority=$closure_status"
    echo "stage1-provenance=$stage1_status"
    echo "canonical-syntax-probe=$probe_status"
    echo "canonical-syntax-probe-exit=$probe_exit"
    echo "embedded-marker=$embedded_marker"
    echo "runtime-delegation=$runtime_delegation"
    echo "semantic-delegation=$semantic_delegation"
    echo "no-delegation=$delegation_status"
    if [ -s "$delegation_markers" ]; then
        sed 's/^/delegation-marker=/' "$delegation_markers"
    fi
    if [ -s "$probe_log" ]; then
        sed 's/^/probe-diagnostic=/' "$probe_log"
    fi
    if [ "$verdict" = PASS ]; then
        echo "canonical-source-compilation=PROVEN"
    else
        echo "canonical-source-compilation=NOT_PROVEN"
        echo "first-blocking-capability=$blocker"
    fi
} >"$report"

cat "$report"

if [ "$verdict" != PASS ]; then
    exit 1
fi
