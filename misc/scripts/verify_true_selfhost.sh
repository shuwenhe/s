#!/usr/bin/env sh
set -eu

# Report completed checks; never advance past a failed operation.
check_progress() {
    [ "${S_BOOTSTRAP_PROGRESS:-0}" = 1 ] || return 0
    progress_done=$1
    progress_total=$2
    progress_label=$3
    progress_bar=
    progress_index=0
    while [ "$progress_index" -lt 20 ]; do
        if [ "$progress_index" -lt "$((progress_done * 20 / progress_total))" ]; then
            progress_bar="${progress_bar}#"
        else
            progress_bar="${progress_bar}-"
        fi
        progress_index=$((progress_index + 1))
    done
    printf '  CHECK [%s] %s/%s %s\n' "$progress_bar" "$progress_done" "$progress_total" "$progress_label" >&2
}



binary=${1:-}

readelf_cmd=${S_BOOTSTRAP_READELF:-readelf}

nm_cmd=${S_BOOTSTRAP_NM:-nm}

strings_cmd=${S_BOOTSTRAP_STRINGS:-strings}



fail() {

    printf '%s\n' "true-selfhost verification failed: $*" >&2

    exit 1

}



[ -n "$binary" ] || fail "usage: $0 <compiler-binary>"

[ -f "$binary" ] || fail "artifact not found: $binary"

[ -x "$binary" ] || fail "artifact is not executable: $binary"



command -v "$readelf_cmd" >/dev/null 2>&1 || fail "readelf is required"

command -v "$nm_cmd" >/dev/null 2>&1 || fail "nm is required"

command -v "$strings_cmd" >/dev/null 2>&1 || fail "strings is required"



check_progress 0 5 "ELF verification: $binary"

header=$("$readelf_cmd" -hW "$binary")

printf '%s\n' "$header" | grep -q 'Class:[[:space:]]*ELF64' || fail "artifact is not ELF64"

printf '%s\n' "$header" | grep -q 'Machine:[[:space:]]*Advanced Micro Devices X86-64' || fail "artifact is not Linux/amd64"



check_progress 1 5 "ELF header verified; checking interpreter"

program_headers=$("$readelf_cmd" -lW "$binary")

if printf '%s\n' "$program_headers" | grep -q '[[:space:]]INTERP[[:space:]]'; then

    fail "artifact contains a dynamic interpreter"

fi



check_progress 2 5 "interpreter verified; checking dependencies"

dynamic=$("$readelf_cmd" -dW "$binary" 2>/dev/null || true)

if printf '%s\n' "$dynamic" | grep -q '(NEEDED)'; then

    fail "artifact has shared-library dependencies"

fi



check_progress 3 5 "dependencies verified; checking symbols"

symbols=$("$nm_cmd" -a "$binary" 2>/dev/null || true)

if printf '%s\n' "$symbols" | grep -Eq 'seed_(compile|bootstrap)|runtime_execute_text|emit_native_from_ir_file|__libc_|@GLIBC'; then

    fail "artifact contains seed compiler, C interpreter, or libc symbols"

fi



check_progress 4 5 "symbols verified; checking embedded paths"

payload=$("$strings_cmd" -a "$binary")

if printf '%s\n' "$payload" | grep -Eq 'src/cmd/compile/seed|/bin/s_seed|S_BOOTSTRAP_BASE_COMPILER|/app/s/bin/s_arm64|base_compiler_path'; then

    fail "artifact embeds a seed compiler or forwarding-launcher path"

fi



check_progress 5 5 "artifact verification done"

printf '%s\n' "true-selfhost verification passed: $binary"
