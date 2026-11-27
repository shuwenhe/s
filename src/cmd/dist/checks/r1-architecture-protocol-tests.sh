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

# Bootstrap dispatch checks
set +e
S_TARGET_OS=linux S_TARGET_ARCH=arm64 bash "$root/src/cmd/dist/native-bootstrap-no-manifest.sh" "$tmp/bootstrap-arm64" >"$tmp/bootstrap-arm64.out" 2>&1
status_arm64=$?
set -e
[ "$status_arm64" -ne 0 ] || { echo "FAIL[bootstrap_arm64]: expected explicit not-implemented failure" >&2; exit 1; }
grep -q 'not implemented in R1' "$tmp/bootstrap-arm64.out" || {
    echo "FAIL[bootstrap_arm64]: missing actionable arm64 message" >&2
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

# Source-level protocol markers
grep -q 'S-NATIVE-AMD64-V1' "$root/src/cmd/compile/internal/compiler/main.s"
grep -q 'S-NATIVE-ARM64-V1' "$root/src/cmd/compile/internal/compiler/main.s"
grep -q 'artifact target mismatch' "$root/src/cmd/compile/internal/compiler/main.s"

echo "R1 architecture/protocol checks passed."
