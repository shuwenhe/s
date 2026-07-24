#!/usr/bin/env sh
set -eu

binary=${1:-}

fail() {
    printf '%s\n' "true-selfhost verification failed: $*" >&2
    exit 1
}

[ -n "$binary" ] || fail "usage: $0 <compiler-binary>"
[ -f "$binary" ] || fail "artifact not found: $binary"
[ -x "$binary" ] || fail "artifact is not executable: $binary"

command -v readelf >/dev/null 2>&1 || fail "readelf is required"
command -v nm >/dev/null 2>&1 || fail "nm is required"
command -v strings >/dev/null 2>&1 || fail "strings is required"

header=$(readelf -hW "$binary")
printf '%s\n' "$header" | grep -q 'Class:[[:space:]]*ELF64' || fail "artifact is not ELF64"
printf '%s\n' "$header" | grep -q 'Machine:[[:space:]]*Advanced Micro Devices X86-64' || fail "artifact is not Linux/amd64"

program_headers=$(readelf -lW "$binary")
if printf '%s\n' "$program_headers" | grep -q '[[:space:]]INTERP[[:space:]]'; then
    fail "artifact contains a dynamic interpreter"
fi

dynamic=$(readelf -dW "$binary" 2>/dev/null || true)
if printf '%s\n' "$dynamic" | grep -q '(NEEDED)'; then
    fail "artifact has shared-library dependencies"
fi

symbols=$(nm -a "$binary" 2>/dev/null || true)
if printf '%s\n' "$symbols" | grep -Eq 'seed_(compile|bootstrap)|runtime_execute_text|emit_native_from_ir_file|__libc_|@GLIBC'; then
    fail "artifact contains seed compiler, C interpreter, or libc symbols"
fi

payload=$(strings -a "$binary")
if printf '%s\n' "$payload" | grep -Eq 'src/cmd/compile/seed|/bin/s_seed|S_BOOTSTRAP_BASE_COMPILER|/app/s/bin/s_arm64|base_compiler_path'; then
    fail "artifact embeds a seed compiler or forwarding-launcher path"
fi

printf '%s\n' "true-selfhost verification passed: $binary"
