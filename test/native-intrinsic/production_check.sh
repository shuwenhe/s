#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-native-intrinsic-production.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package main
extern "intrinsic" func host_args() string[]
extern "intrinsic" func __host_write_text_file(string path, string text) int
extern "intrinsic" func __host_read_to_string(string path) string
extern "intrinsic" func runtime_env_get(string key, string fallback) string
extern "intrinsic" func __int_to_string(int value) string
func main() int {
    args := host_args()
    if len(args) != 2 { return 1 }
    if __host_write_text_file(args[1], "native 世界") != 0 { return 2 }
    text := __host_read_to_string(args[1])
    if text != "native 世界" { return 3 }
    eprintln(runtime_env_get("S_NATIVE_INTRINSIC_TEST", "missing"))
    println(__int_to_string(-40))
    return 0
}
S
"$compiler" --compile-unit "$work/main.sasm" "$work/main.s"
"$compiler" --emit-bin "$work/main.sasm" "$work/main"
S_NATIVE_INTRINSIC_TEST=env-value "$work/main" "$work/written" > "$work/stdout" 2> "$work/stderr"
test "$(cat "$work/written")" = 'native 世界'
test "$(cat "$work/stdout")" = '-40'
test "$(cat "$work/stderr")" = 'env-value'
printf preserved > "$work/preserved.sasm"
for mode in unknown signature; do
    if [ "$mode" = unknown ]; then
        printf 'package main\nextern "intrinsic" func unchecked() int\nfunc main() int { return unchecked() }\n' > "$work/bad.s"
    else
        printf 'package main\nextern "intrinsic" func host_args() int\nfunc main() int { return host_args() }\n' > "$work/bad.s"
    fi
    if "$compiler" --compile-unit "$work/preserved.sasm" "$work/bad.s" > "$work/$mode.log" 2>&1; then
        echo "native compiler accepted $mode intrinsic declaration" >&2; exit 1
    fi
    test "$(cat "$work/preserved.sasm")" = preserved
done
echo 'canonical native intrinsic declarations and builtin calls: PASS'
