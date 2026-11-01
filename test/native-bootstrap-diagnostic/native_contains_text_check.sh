#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-contains.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo "contains artifacts: $work" >&2; fi' EXIT
cat > "$work/main.s" <<'S'
package main
extern "intrinsic" func contains_text(string haystack, string needle) bool
extern "intrinsic" func __host_read_to_string(string path) string
func check(string missing_path) () {
    if !contains_text("abcdef", "bcd") { panic("substring") }
    if contains_text("abcdef", "xyz") { panic("absent") }
    if contains_text("ab", "abcd") { panic("long needle") }
    if contains_text("", "a") { panic("empty haystack") }
    if !contains_text("abc", "") || !contains_text("", "") { panic("empty needle") }
    if !contains_text("aaaaab", "aaab") { panic("repeated prefix") }
    if !contains_text("abcdef", "ef") || !contains_text("abcdef", "abcdef") { panic("boundary") }
    rope := "ab" + "cd" + "ef"
    needle := "c" + "d" + "e"
    if !contains_text(rope, "cde") || !contains_text(rope, needle) { panic("rope") }
    if contains_text(rope, "cdx") { panic("rope absent") }
    missing := __host_read_to_string(missing_path)
    if contains_text(missing, "x") || !contains_text(missing, "") { panic("null string") }
}
func main() int { args := host_args(); check(args[1]); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" "$work/missing" || status=$?
test "$status" -eq 42
python3 - "$work" <<'PY'
from pathlib import Path
import sys
w=Path(sys.argv[1]);s=(w/'main.ir').read_text();s=s.replace('ARG|"abcdef"|_|_','ARG|42|_|_',1);(w/'wrong.ir').write_text(s)
PY
printf 'preserve\n' > "$work/output"
cp "$work/output" "$work/saved"
if S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/wrong.ir" "$work/output" > "$work/wrong.log" 2>&1; then
    echo 'contains_text accepted an integer as a string' >&2; exit 1
fi
cmp "$work/output" "$work/saved"
echo 'native contains_text: flat/rope/null/boundary semantics and typed rejection PASS'
