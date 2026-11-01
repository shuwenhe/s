#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-host-tools.XXXXXX)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/parent with space"
printf keep > "$work/parent with space/keep"
ln "$work/parent with space/keep" "$work/parent with space/hard alias"
ln -s keep "$work/parent with space/symbolic alias"
printf keep > "$work/parent with space/different"
cat > "$work/tools.s" <<'S'
package main
struct borrow_probe { int value }
func native_host_probe_set(target* borrow_probe) { target.value = 42 }
func native_host_probe() int {
    value := borrow_probe {}
    native_host_probe_set(value)
    return value.value
}
extern "intrinsic" func __host_run_argv(string[] args) int
extern "intrinsic" func __host_make_temp_dir_in(string directory) string
extern "intrinsic" func __host_write_text_file(string path, string data) int
extern "intrinsic" func __host_read_source(string path) string
extern "intrinsic" func __host_rename_file(string from, string to) int
extern "intrinsic" func __host_make_executable(string path) int
extern "intrinsic" func __host_byte_string(int value) string
extern "intrinsic" func __host_env_get(string key, string fallback) string
extern "intrinsic" func __host_same_file(string left, string right) bool
func main() int {
    args := host_args()
    parent := args[1]
    original := parent + "/keep"
    if !__host_same_file(original, original) { return 22 }
    if !__host_same_file(original, parent + "/hard alias") { return 23 }
    if !__host_same_file(parent + "/symbolic alias", original) { return 24 }
    if __host_same_file(original, parent + "/different") { return 25 }
    if __host_same_file(parent + "/missing", parent + "/missing") { return 26 }
    if __host_run_argv(["/bin/sh", "-c", "exit 23"]) != 23 { return 1 }
    if __host_run_argv(["sh", "-c", "test \"$S_PROC_TOKEN\" = \"inherited value\""]) != 0 { return 2 }
    if __host_run_argv(["s-native-command-that-does-not-exist"]) != 127 { return 3 }
    if __host_run_argv(["sh", "-c", "kill -TERM $$"]) != 143 { return 4 }
    if __host_run_argv(string[]()) == 0 { return 5 }
    if __host_env_get("S_PROC_TOKEN", "missing") != "inherited value" { return 6 }
    if __host_env_get("S_NATIVE_UNSET_TOKEN", "fallback") != "fallback" { return 7 }
    shell := "s" + "h"
    if __host_run_argv([shell, "-c", "test \"$1\" = '' && test \"$2\" = 'a b;$ literal'", "s-test", "", "a b;$ literal"]) != 0 { return 19 }
    zero := __host_byte_string(0)
    if __host_same_file(original + zero + "suffix", original) { return 27 }
    nul_command := "exit 0" + zero
    if __host_run_argv(["sh", "-c", nul_command]) != -1 { return 20 }
    first := __host_make_temp_dir_in(parent)
    second := __host_make_temp_dir_in(parent)
    if first == "" || second == "" || first == parent || first == second { return 8 }
    if __host_write_text_file(first + "/bad" + zero + "suffix", "data") == 0 { return 21 }
    text_path := first + "/file with space"
    if __host_write_text_file(text_path, "rope " + "payload") != 0 { return 9 }
    if __host_read_source(text_path) != "rope payload" { return 10 }
    source := first + "/program.s"
    object := first + "/program.o"
    binary := first + "/program"
    assembly := ".global _start\n.text\n_start:\n mov $60, %rax\n mov $42, %rdi\n syscall\n"
    if __host_write_text_file(source, assembly) != 0 { return 11 }
    if __host_run_argv(["as", "--64", "-o", object, source]) != 0 { return 12 }
    if __host_run_argv(["ld", "-m", "elf_x86_64", "-nostdlib", "-o", binary, object]) != 0 { return 13 }
    if __host_make_executable(binary) != 0 { return 14 }
    if __host_run_argv([binary]) != 42 { return 15 }
    final := parent + "/final"
    if __host_rename_file(binary, final) != 0 { return 16 }
    if __host_run_argv([final]) != 42 { return 17 }
    if __host_run_argv(["rm", "-rf", "--", first, second]) != 0 { return 18 }
    return native_host_probe()
}
S
"$root/bin/s_seed" --compile-native-unit "$work/tools.ir" "$work/tools.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/tools.ir" "$work/tools"
env_bin=$(command -v env)
timeout_bin=$(command -v timeout)
mkdir -p "$work/tool-path"
for tool in sh as ld rm; do ln -s "$(command -v "$tool")" "$work/tool-path/$tool"; done
for mode in inherited unset search; do
    status=0
    case "$mode" in
        inherited) "$env_bin" -u S_NATIVE_UNSET_TOKEN S_PROC_TOKEN='inherited value' "$timeout_bin" 20 "$work/tools" "$work/parent with space" || status=$? ;;
        unset) "$env_bin" -u S_NATIVE_UNSET_TOKEN -u PATH S_PROC_TOKEN='inherited value' "$timeout_bin" 20 "$work/tools" "$work/parent with space" || status=$? ;;
        search) "$env_bin" -u S_NATIVE_UNSET_TOKEN PATH=":/does-not-exist:$work/tool-path" S_PROC_TOKEN='inherited value' "$timeout_bin" 20 "$work/tools" "$work/parent with space" || status=$? ;;
    esac
    if [ "$status" -ne 42 ]; then echo "native host tools $mode: expected42, got$status" >&2; exit 1; fi
done
test "$(cat "$work/parent with space/keep")" = keep
test "$(find "$work/parent with space" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 0
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/parent with space/final"
echo 'native argv/env/status, private directories, rope paths, as/ld/ELF execution: PASS'
