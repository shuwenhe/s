#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-string-index.XXXXXX)
trap 'rm -rf "$work"' EXIT
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import sys
root,work=map(Path,sys.argv[1:]); source=(root/'src/cmd/compile/internal/abi/abiutils.s').read_text()
start=source.index('func starts_with('); first=source.index('{',start); depth=1; end=first+1
while depth:
    depth+=(source[end]=='{')-(source[end]=='}'); end+=1
(work/'main.s').write_text('package main\n'+source[start:end]+'''
func check_conversion() () {
    text := "abc"
    if string(text[1]) != "b" { panic("character conversion failed") }
    if string(42) != "42" { panic("integer conversion failed") }
}
func measured(string input) int { return input.len() }
func main() int {
    check_conversion()
    plain := "abcdef"
    rope := "abc" + "def"
    if plain[1] != "b" || rope[4] != "e" { return 1 }
    if !starts_with(plain, "abc") || !starts_with(rope, "abcd") { return 2 }
    if starts_with(rope, "abx") { return 3 }
    if measured(rope) != 6 { return 4 }
    numbers := [11, 31]
    return numbers[0] + numbers[1]
}
''')
PY
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'native flat/rope string indices, method length and production prefix helper: PASS'
