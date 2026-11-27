#!/usr/bin/env bash
set -euo pipefail

root=$(cd "${S_SOURCE_ROOT:-$(dirname "$0")/../../../..}" && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/s-r1-arch-tests.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

fake_compiler="$tmp/fake-compiler.sh"
cat > "$fake_compiler" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
log_file=${FAKE_LOG:?}
echo "$*" >> "$log_file"
if [ "${1:-}" = "--compile-unit" ]; then
    out=$2
    case "${FAKE_HEADER_ARCH:-amd64}" in
        amd64) printf '# S-NATIVE-AMD64-V1\n.text\n' > "$out" ;;
        arm64) printf '# S-NATIVE-ARM64-V1\n.text\n' > "$out" ;;
        malformed) printf 'NOT-A-NATIVE-HEADER\n' > "$out" ;;
        unknown) printf '# S-NATIVE-ARM64-V9\n.text\n' > "$out" ;;
        empty) : > "$out" ;;
        truncated_amd64) printf '# S-NATIVE-AMD64-V1' > "$out" ;;
        truncated_arm64) printf '# S-NATIVE-ARM64-V1' > "$out" ;;
        bad_newline_amd64) printf '# S-NATIVE-AMD64-V1\r\n.text\r\n' > "$out" ;;
        bad_newline_arm64) printf '# S-NATIVE-ARM64-V1\r\n.text\r\n' > "$out" ;;
        *) exit 2 ;;
    esac
    exit 0
fi
if [ "${1:-}" = "--emit-bin" ]; then
    echo "emit-bin-called" >> "$log_file"
    exit 99
fi
exit 2
EOF
chmod +x "$fake_compiler"

assert_case() {
    local name=$1
    local target_arch=$2
    local header_arch=$3
    local want_emit=$4
    local log="$tmp/$name.log"
    local out="$tmp/$name.out"
    local status=0
    : > "$log"
    set +e
    FAKE_LOG="$log" FAKE_HEADER_ARCH="$header_arch" S_TARGET_ARCH="$target_arch" \
        bash "$root/src/cmd/dist/checks/selfhost-execution.sh" "$fake_compiler" "$tmp/$name-work" >"$out" 2>&1
    status=$?
    set -e
    got_emit=0
    if grep -q 'emit-bin-called' "$log"; then
        got_emit=1
    fi
    if [ "$want_emit" = 1 ]; then
        [ "$got_emit" -eq 1 ] || { echo "FAIL[$name]: expected artifact acceptance" >&2; exit 1; }
        [ "$status" -eq 99 ] || { echo "FAIL[$name]: expected emit-bin status 99, got $status" >&2; exit 1; }
    else
        [ "$got_emit" -eq 0 ] || { echo "FAIL[$name]: expected artifact rejection" >&2; exit 1; }
        [ "$status" -ne 99 ] || { echo "FAIL[$name]: unexpected artifact acceptance" >&2; exit 1; }
    fi
}

# Artifact protocol checks
assert_case amd64_accepts_amd64 amd64 amd64 1
assert_case arm64_accepts_arm64 arm64 arm64 1
assert_case amd64_rejects_arm64 amd64 arm64 0
assert_case arm64_rejects_amd64 arm64 amd64 0
assert_case amd64_rejects_malformed amd64 malformed 0
assert_case arm64_rejects_unknown arm64 unknown 0
assert_case amd64_rejects_empty amd64 empty 0
assert_case arm64_rejects_empty arm64 empty 0
assert_case amd64_rejects_truncated amd64 truncated_amd64 0
assert_case arm64_rejects_truncated arm64 truncated_arm64 0
assert_case amd64_rejects_bad_newline amd64 bad_newline_amd64 0
assert_case arm64_rejects_bad_newline arm64 bad_newline_arm64 0

# Platform compatibility checks at script boundary
set +e
FAKE_LOG="$tmp/platform-arch.log" FAKE_HEADER_ARCH=amd64 S_TARGET_ARCH=riscv64 \
    bash "$root/src/cmd/dist/checks/selfhost-execution.sh" "$fake_compiler" "$tmp/platform-arch-work" >"$tmp/platform-arch.out" 2>&1
status_arch=$?
set -e
[ "$status_arch" -eq 2 ] || { echo "FAIL[unsupported_arch]: expected exit 2, got $status_arch" >&2; exit 1; }
grep -q 'unsupported target arch for artifact checks: riscv64' "$tmp/platform-arch.out" || {
    echo "FAIL[unsupported_arch]: missing diagnostic" >&2
    exit 1
}

# Bootstrap dispatch checks
# AMD64 dispatch path should be selected (then fail later if seed is absent)
mkdir -p "$tmp/no-manifest-root/src/cmd/compile"
printf 'package compile\n' > "$tmp/no-manifest-root/src/cmd/compile/main.s"
set +e
S_SOURCE_ROOT="$tmp/no-manifest-root" S_TARGET_OS=linux S_TARGET_ARCH=amd64 \
    bash "$root/src/cmd/dist/native-bootstrap-no-manifest.sh" "$tmp/bootstrap-amd64" >"$tmp/bootstrap-amd64.out" 2>&1
status_amd64=$?
set -e
[ "$status_amd64" -ne 0 ] || { echo "FAIL[bootstrap_amd64]: expected failure due missing seed in fixture root" >&2; exit 1; }
grep -q 'seed compiler not found' "$tmp/bootstrap-amd64.out" || {
    echo "FAIL[bootstrap_amd64]: expected amd64 path to reach seed check" >&2
    exit 1
}
if grep -q 'unsupported target' "$tmp/bootstrap-amd64.out" || grep -q 'not implemented in R1' "$tmp/bootstrap-amd64.out"; then
    echo "FAIL[bootstrap_amd64]: amd64 dispatch unexpectedly treated as unsupported/arm64" >&2
    exit 1
fi

set +e
S_TARGET_OS=linux S_TARGET_ARCH=arm64 bash "$root/src/cmd/dist/native-bootstrap-no-manifest.sh" "$tmp/bootstrap-arm64" >"$tmp/bootstrap-arm64.out" 2>&1
status_arm64=$?
set -e
[ "$status_arm64" -ne 0 ] || { echo "FAIL[bootstrap_arm64]: expected explicit not-implemented failure" >&2; exit 1; }
grep -q 'not implemented in R1' "$tmp/bootstrap-arm64.out" || {
    grep -q 'linux/arm64 native bootstrap is currently blocked' "$tmp/bootstrap-arm64.out" || {
    grep -q 'arm64 standalone unsupported IR op:' "$tmp/bootstrap-arm64.out" || {
    echo "FAIL[bootstrap_arm64]: missing actionable arm64 message" >&2
    exit 1
    }
    }
}
[ ! -e "$tmp/bootstrap-arm64/.complete" ] || {
    echo "FAIL[bootstrap_arm64]: stale .complete marker left behind" >&2
    exit 1
}

set +e
S_TARGET_OS=darwin S_TARGET_ARCH=arm64 bash "$root/src/cmd/dist/native-bootstrap-no-manifest.sh" "$tmp/bootstrap-unsupported" >"$tmp/bootstrap-unsupported.out" 2>&1
status_unsupported=$?
set -e
[ "$status_unsupported" -ne 0 ] || { echo "FAIL[bootstrap_unsupported]: expected unsupported-target failure" >&2; exit 1; }
grep -q 'unsupported target' "$tmp/bootstrap-unsupported.out" || {
    echo "FAIL[bootstrap_unsupported]: expected unsupported-target diagnostic" >&2
    exit 1
}
[ ! -e "$tmp/bootstrap-unsupported/.complete" ] || {
    echo "FAIL[bootstrap_unsupported]: stale .complete marker left behind" >&2
    exit 1
}

# no-manifest bootstrap must clear stale completion marker on failure
mkdir -p "$tmp/bootstrap-stale"
touch "$tmp/bootstrap-stale/.complete"
set +e
S_TARGET_OS=linux S_TARGET_ARCH=arm64 bash "$root/src/cmd/dist/native-bootstrap-no-manifest.sh" "$tmp/bootstrap-stale" >"$tmp/bootstrap-stale.out" 2>&1
status_stale=$?
set -e
[ "$status_stale" -ne 0 ] || { echo "FAIL[bootstrap_stale]: expected failure" >&2; exit 1; }
[ ! -e "$tmp/bootstrap-stale/.complete" ] || {
    echo "FAIL[bootstrap_stale]: stale .complete marker not removed" >&2
    exit 1
}

# native-bootstrap dispatch tests
set +e
S_TARGET_OS=linux S_TARGET_ARCH=arm64 sh "$root/src/cmd/dist/native-bootstrap.sh" "$tmp/native-bootstrap-arm64" >"$tmp/native-bootstrap-arm64.out" 2>&1
status_native_arm64=$?
set -e
[ "$status_native_arm64" -eq 2 ] || { echo "FAIL[native_bootstrap_arm64]: expected exit 2, got $status_native_arm64" >&2; exit 1; }
grep -q 'recognized but not implemented in R1' "$tmp/native-bootstrap-arm64.out" || {
    grep -q 'native bootstrap linux/arm64 is currently blocked' "$tmp/native-bootstrap-arm64.out" || {
    echo "FAIL[native_bootstrap_arm64]: missing arm64 not-implemented diagnostic" >&2
    exit 1
    }
}

set +e
S_TARGET_OS=darwin S_TARGET_ARCH=arm64 sh "$root/src/cmd/dist/native-bootstrap.sh" "$tmp/native-bootstrap-unsupported" >"$tmp/native-bootstrap-unsupported.out" 2>&1
status_native_unsupported=$?
set -e
[ "$status_native_unsupported" -eq 2 ] || { echo "FAIL[native_bootstrap_unsupported]: expected exit 2, got $status_native_unsupported" >&2; exit 1; }
grep -q 'supports S_TARGET_OS=linux' "$tmp/native-bootstrap-unsupported.out" || {
    echo "FAIL[native_bootstrap_unsupported]: missing unsupported-target diagnostic" >&2
    exit 1
}

# host/target mismatch (amd64 target on arm64 host without runner) must fail explicitly
set +e
S_TARGET_OS=linux S_TARGET_ARCH=amd64 sh "$root/src/cmd/dist/native-bootstrap.sh" "$tmp/native-bootstrap-amd64" >"$tmp/native-bootstrap-amd64.out" 2>&1
status_native_mismatch=$?
set -e
[ "$status_native_mismatch" -eq 2 ] || { echo "FAIL[native_bootstrap_mismatch]: expected exit 2, got $status_native_mismatch" >&2; exit 1; }
grep -q 'set S_BOOTSTRAP_RUNNER to a target executor' "$tmp/native-bootstrap-amd64.out" || {
    echo "FAIL[native_bootstrap_mismatch]: missing runner mismatch diagnostic" >&2
    exit 1
}

# Source-level protocol markers
grep -q 'S-NATIVE-AMD64-V1' "$root/src/cmd/compile/internal/compiler/main.s"
grep -q 'S-NATIVE-ARM64-V1' "$root/src/cmd/compile/internal/compiler/main.s"
grep -q 'artifact target mismatch' "$root/src/cmd/compile/internal/compiler/main.s"
grep -q 'unknown native assembly artifact protocol version' "$root/src/cmd/compile/internal/compiler/main.s"
grep -q 'malformed native assembly artifact header' "$root/src/cmd/compile/internal/compiler/main.s"

echo "R1 architecture/protocol checks passed."
