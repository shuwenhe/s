#!/bin/sh
# Build native S Redis tests with the existing verified OpenSSL bridge; no Python.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
mode=${1:?usage: build-redis-test.sh MODE OUTPUT}
output=${2:?usage: build-redis-test.sh MODE OUTPUT}
case "$output" in /*) ;; *) output="$PWD/$output" ;; esac
work=$(mktemp -d "${TMPDIR:-/tmp}/s-redis-build.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT HUP INT TERM
cd "$root"
export S_SOURCE_ROOT="$root"
compiler=${S_TEST_COMPILER:-"$root/bin/s_compiler"}
case "$mode" in
    protocol-seed|protocol-native)
        cat > "$work/main.s" <<'SOURCE'
package main
func main() int {
    return protocol_checks()
}
SOURCE
        if [ "$mode" = protocol-seed ]; then
            compiler="$root/bin/s_seed"
            compile_flag=--compile-native-unit
            emit_flag=--emit-standalone-amd64
        else
            compile_flag=--compile-unit
            emit_flag=--emit-bin
        fi
        "$compiler" "$compile_flag" "$work/program.ir" "$work/main.s" \
            test/redis/protocol.s src/std/redis/types.s src/std/redis/protocol.s \
            src/result/result.s src/prelude/prelude.s
        "$compiler" "$emit_flag" "$work/program.ir" "$work/program"
        ;;
    suite|peer|basic)
        case "$mode" in
            suite) cat test/redis/*.s > "$work/combined.s" ;;
            peer) cat test/redis/peer/main.s > "$work/combined.s" ;;
            basic) cat test/redis/basic/main.s > "$work/combined.s" ;;
        esac
        for source in src/std/redis/*.s src/std/tcp.s src/std/tls.s src/std/time.s \
            src/std/string.s src/result/result.s src/prelude/prelude.s; do
            printf '\n' >> "$work/combined.s"
            cat "$source" >> "$work/combined.s"
        done
        "$compiler" --emit-amd64 "$work/combined.s" "$work/program.s"
        # Match the repository's existing OpenSSL builder startup ABI.
        {
            printf '\n.text\n.globl s_native_initialize_process\n'
            printf '.type s_native_initialize_process,@function\ns_native_initialize_process:\n'
            if awk '/^\.Ls_native_envp:/{found=1} END{exit !found}' "$work/program.s"; then
                printf '  movq %%rdi,.Ls_native_argc(%%rip)\n'
                printf '  movq %%rsi,.Ls_native_argv(%%rip)\n'
                printf '  movq %%rdx,.Ls_native_envp(%%rip)\n'
            fi
            printf '  ret\n.section .note.GNU-stack,"",@progbits\n'
        } >> "$work/program.s"
        "${S_BOOTSTRAP_AS:-as}" --64 "$work/program.s" -o "$work/program.o"
        cat > "$work/startup.c" <<'STARTUP'
#include <stdint.h>
extern long s_native_entry(void);
extern uintptr_t s_native_gc_stack_top __attribute__((weak));
extern void s_native_initialize_globals(void) __attribute__((weak));
extern void s_native_initialize_process(long, char **, char **);
int main(int argc, char **argv, char **envp) {
    uintptr_t stack_anchor = 0;
    s_native_initialize_process(argc, argv, envp);
    if (&s_native_gc_stack_top) s_native_gc_stack_top = (uintptr_t)&stack_anchor;
    if (s_native_initialize_globals) s_native_initialize_globals();
    return (int)s_native_entry();
}
STARTUP
        "${CC:-cc}" -std=c11 -O2 -Wall -Wextra -Werror -no-pie \
            "$work/startup.c" "$work/program.o" src/runtime/native_tls_openssl.c \
            -lssl -lcrypto -o "$work/program"
        ;;
    *) echo "unknown Redis build mode: $mode" >&2; exit 2 ;;
esac
mkdir -p -- "$(dirname -- "$output")"
cp -- "$work/program" "$output"
chmod +x -- "$output"
