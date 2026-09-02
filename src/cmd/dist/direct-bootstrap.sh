#!/bin/sh
set -eu

root=${S_SOURCE_ROOT:-$(pwd)}
work=${1:-"$root/.bootstrap/direct"}
stage1=${S_DIRECT_BOOTSTRAP_STAGE1:-"$root/bin/s"}
source_file=${S_BOOTSTRAP_SOURCE:-"$root/src/cmd/compile/selfhost/compiler.s"}
verify="$root/misc/scripts/verify_true_selfhost.sh"
timeout_seconds=${S_DIRECT_BOOTSTRAP_TIMEOUT:-120}

# shellcheck source=target-env.sh
. "$root/src/cmd/dist/target-env.sh"
s_target_init
if ! s_target_is_linux_amd64; then
    printf '%s\n' "direct bootstrap supports S_TARGET_OS=linux and S_TARGET_ARCH=amd64; got $S_TARGET_OS/$S_TARGET_ARCH" >&2
    exit 2
fi
s_target_select_linux_amd64_tools
if s_target_needs_runner && [ -z "${S_BOOTSTRAP_RUNNER:-}" ]; then
    printf '%s\n' "direct bootstrap target $S_TARGET_OS/$S_TARGET_ARCH differs from host $S_HOST_OS/$S_HOST_ARCH; set S_BOOTSTRAP_RUNNER to a target executor" >&2
    exit 2
fi

run_stage() {
    if [ -n "${S_BOOTSTRAP_RUNNER:-}" ]; then
        "$S_BOOTSTRAP_RUNNER" "$@"
    else
        "$@"
    fi
}

run_with_timeout() {
    if [ -n "${S_BOOTSTRAP_RUNNER:-}" ]; then
        set -- "$S_BOOTSTRAP_RUNNER" "$@"
    fi
    if command -v timeout >/dev/null 2>&1; then
        timeout "$timeout_seconds" "$@"
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$timeout_seconds" "$@"
    else
        "$@"
    fi
}

fail() {
    printf '%s\n' "direct bootstrap failed: $*" >&2
    exit 1
}

report_frontier() {
    report="$work/frontier.unsupported.txt"
    if run_with_timeout "$stage1" --report-unsupported \
        "$source_file" "$report" >/dev/null 2>&1; then
        printf '%s\n' "bootstrap frontier:" >&2
        sed -n '3,$p' "$report" >&2
    else
        printf '%s\n' "bootstrap frontier: stage1 report unavailable" >&2
    fi
}

[ -x "$stage1" ] || fail "stage1 compiler not found: $stage1"
[ -f "$source_file" ] || fail "compiler source not found: $source_file"
[ -x "$verify" ] || fail "self-host verifier not found: $verify"

mkdir -p "$work"

# No compiler stage in this script may emit assembly or invoke as/ld. Each
# compiler must write the next ELF image directly from the S compiler source.
printf '%s\n' "[1/4] stage1 -> stage2 (direct ELF)"
run_with_timeout "$stage1" build "$source_file" -o "$work/stage2" ||
    { report_frontier; fail "stage1 cannot directly compile the complete S compiler yet"; }
S_BOOTSTRAP_READELF="$S_BOOTSTRAP_READELF" S_BOOTSTRAP_NM="$S_BOOTSTRAP_NM" S_BOOTSTRAP_STRINGS="$S_BOOTSTRAP_STRINGS" "$verify" "$work/stage2"

printf '%s\n' "[2/4] stage2 -> stage3 (direct ELF)"
run_with_timeout "$work/stage2" build "$source_file" -o "$work/stage3" ||
    fail "stage2 cannot directly compile the complete S compiler"
S_BOOTSTRAP_READELF="$S_BOOTSTRAP_READELF" S_BOOTSTRAP_NM="$S_BOOTSTRAP_NM" S_BOOTSTRAP_STRINGS="$S_BOOTSTRAP_STRINGS" "$verify" "$work/stage3"

printf '%s\n' "[3/4] deterministic convergence"
cmp "$work/stage2" "$work/stage3" ||
    fail "stage2 and stage3 machine-code images differ"

printf '%s\n' "[4/4] generated compiler smoke test"
run_with_timeout "$work/stage3" build "$root/test/selfhost/bootstrap_whole_program.s" \
    -o "$work/smoke"
set +e
run_stage "$work/smoke"
status=$?
set -e
[ "$status" -eq 42 ] || fail "generated program returned $status, want 42"

printf '%s\n' "DIRECT MACHINE-CODE SELF-HOST PASS"
