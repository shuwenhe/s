#!/bin/sh
set -eu

root=${S_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
stage1=${MODULAR_STAGE1_BIN:-"$root/.bootstrap/modular/s_modular-stage1"}
report=${STAGE1_DELEGATION_AUTHORITY_REPORT:-"$root/.bootstrap/modular/stage1-delegation-authority-report.txt"}

mkdir -p "$(dirname -- "$report")"

tmp=${TMPDIR:-/tmp}/stage1-delegation-authority.$$
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

probe="$tmp/canonical_probe.s"
probe_out="$tmp/canonical_probe"
probe_log="$tmp/canonical_probe.log"
marker_log="$tmp/embedded_markers.txt"

cat >"$probe" <<'SRC'
package cmd
import ()
func main() int {
    return 7
}
SRC

if [ ! -x "$stage1" ]; then
    {
        echo "stage1-delegation-authority-check"
        echo "stage1-present=FAIL"
        echo "embedded-marker=UNKNOWN"
        echo "runtime-delegation=UNKNOWN"
        echo "semantic-delegation=UNKNOWN"
        echo "canonical-probe-build=FAIL"
        echo "canonical-probe-exit=NOT_RUN"
        echo "stage1-delegation-authority=NOT_PROVEN"
        echo "first-blocking-capability=stage1-missing-or-not-executable"
    } >"$report"
    cat "$report"
    exit 1
fi

strings "$stage1" 2>/dev/null |
    grep -E 'bin/s_seed|s_seed --emit|bootstrap-subset|artifact-only: canonical-source-compilation=NOT_PROVEN' >"$marker_log" || true

embedded_marker=NO
if [ -s "$marker_log" ]; then
    embedded_marker=YES
fi

set +e
S_PROJECT_ROOT="$root" S_SOURCE_ROOT="$root/src" "$stage1" build "$probe" -o "$probe_out" >"$probe_log" 2>&1
build_status=$?
set -e

canonical_probe_build=FAIL
probe_exit=NOT_RUN
if [ "$build_status" -eq 0 ] && [ -x "$probe_out" ]; then
    canonical_probe_build=PASS
    set +e
    "$probe_out" >/dev/null 2>&1
    probe_exit=$?
    set -e
fi

runtime_delegation=NO
semantic_delegation=NO
if grep -Eq 'bootstrap-subset:|bin/s_seed|s_seed --emit' "$probe_log"; then
    runtime_delegation=YES
fi
if grep -Eq 'fallback|delegate|delegat|bootstrap-subset:|s_seed' "$probe_log"; then
    semantic_delegation=YES
fi

authority=PROVEN
blocker=""
if [ "$canonical_probe_build" != PASS ]; then
    authority=NOT_PROVEN
    blocker=canonical-probe-build-failed
elif [ "$probe_exit" -ne 7 ]; then
    authority=NOT_PROVEN
    blocker=canonical-probe-exit-mismatch
elif [ "$runtime_delegation" = YES ]; then
    authority=NOT_PROVEN
    blocker=runtime-delegation-observed
elif [ "$semantic_delegation" = YES ]; then
    authority=NOT_PROVEN
    blocker=semantic-delegation-observed
fi

{
    echo "stage1-delegation-authority-check"
    echo "stage1-present=PASS"
    echo "embedded-marker=$embedded_marker"
    if [ -s "$marker_log" ]; then
        sed 's/^/embedded-marker-text=/' "$marker_log"
    fi
    echo "runtime-delegation=$runtime_delegation"
    echo "semantic-delegation=$semantic_delegation"
    echo "canonical-probe-build=$canonical_probe_build"
    echo "canonical-probe-exit=$probe_exit"
    if [ -s "$probe_log" ]; then
        sed 's/^/probe-diagnostic=/' "$probe_log"
    fi
    echo "stage1-delegation-authority=$authority"
    if [ "$authority" != PROVEN ]; then
        echo "first-blocking-capability=$blocker"
    fi
} >"$report"

cat "$report"

if [ "$authority" != PROVEN ]; then
    exit 1
fi
