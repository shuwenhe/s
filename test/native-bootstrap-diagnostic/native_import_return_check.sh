#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-import-return.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo "import return artifacts: $work" >&2; fi' EXIT
cat > "$work/producer.s" <<'S'
package producer
struct source_file { int answer }
struct output { source_file file }
func produce() output { return output { file: source_file { answer: 42 } } }
S
cat > "$work/foreign.s" <<'S'
package foreign
struct source_file { string answer }
struct output { source_file file }
func foreign_produce() output { return output { file: source_file { answer: "wrong" } } }
S
cat > "$work/main.s" <<'S'
package main
import "producer"
import "std.result"
struct failure { string message }
func read() result[producer.source_file,failure] {
    made := produce()
    return result.ok(made.file)
}
func main() int { value, error := read(); return value.answer + len(error.message) }
S
for order in first second; do
    sources=("$work/producer.s" "$work/foreign.s")
    if [ "$order" = second ]; then sources=("$work/foreign.s" "$work/producer.s"); fi
    "$root/bin/s_seed" --compile-native-unit "$work/$order.ir" "$root/src/result/result.s" "${sources[@]}" "$work/main.s"
    S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/$order.ir" "$work/$order"
    status=0; "$work/$order" || status=$?; test "$status" -eq 42
done
echo 'imported function return record and nested type identity: PASS'
# A foreign declaration in the closure is not an import in this source file.
sed '/import "producer"/d' "$work/main.s" > "$work/no-import.s"
printf 'preserve\n' > "$work/output"
cp "$work/output" "$work/saved"
if "$root/bin/s_seed" --compile-native-unit "$work/output" "$root/src/result/result.s" "$work/producer.s" "$work/foreign.s" "$work/no-import.s" > "$work/no-import.log" 2>&1; then
    echo 'accepted unimported function return type' >&2; exit 1
fi
cmp "$work/output" "$work/saved"
# Import scopes must not leak between files in the same package.
cat > "$work/sibling.s" <<'S'
package main
import "producer"
func unused() int { return 0 }
S
if "$root/bin/s_seed" --compile-native-unit "$work/output" "$root/src/result/result.s" "$work/producer.s" "$work/foreign.s" "$work/sibling.s" "$work/no-import.s" > "$work/sibling.log" 2>&1; then
    echo 'accepted imported function from sibling file scope' >&2; exit 1
fi
cmp "$work/output" "$work/saved"
sed 's/foreign_produce/produce/' "$work/foreign.s" > "$work/ambiguous.s"
sed '/import "producer"/a import "foreign"' "$work/main.s" > "$work/both.s"
if "$root/bin/s_seed" --compile-native-unit "$work/output" "$root/src/result/result.s" "$work/producer.s" "$work/ambiguous.s" "$work/both.s" > "$work/ambiguous.log" 2>&1; then
    echo 'accepted ambiguous imported function' >&2; exit 1
fi
grep -q 'ambiguous imported function' "$work/ambiguous.log"
cmp "$work/output" "$work/saved"
echo 'unimported, sibling scope and ambiguous import rejection: PASS'
