#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-array-element.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo "array element artifacts: $work" >&2; fi' EXIT
cat > "$work/library.s" <<'S'
package records
struct cell { int amount }
struct collection { cell[] values }
func create() cell[] {
    values := cell[]()
    values.push(cell { amount: 40 })
    return values
}
S
cat > "$work/foreign.s" <<'S'
package foreign
struct cell { string amount }
S
cat > "$work/main.s" <<'S'
package main
import "records"
import "std.result"
import "std.option"
struct failure { string message }
struct item { int value }
func first[t](t[] values) t { return values[0] }
func empty[t](t ignored) t[] { return t[] {} }
func fresh_ints() int[] { return []int{} }
func chosen() option[string] {
    candidates := string[]()
    candidates.push("ok")
    return option.some(candidates[0])
}
func option_length(option[string] input) int {
    switch input { option.some(text): len(text), option.none: 0 }
}
func compute() result[int,failure] {
    candidates := string[]()
    candidates.push("ok")
    literal := [2]
    if literal[0] != 2 { return result.err(failure { message: "literal element" }) }
    argv := host_args()
    if len(argv[0]) == 0 { return result.err(failure { message: "runtime array" }) }
    if candidates[0] != "ok" { return result.err(failure { message: "wrong" }) }
    explicit := fresh_ints()
    explicit.push(2)
    nested_literal := int[][] {}
    nested_literal.push(int[] { 2 })
    instantiated := empty(1)
    instantiated.push(2)
    allocated := make(int[], 1)
    allocated[0] = 2
    if explicit[0] + nested_literal[0][0] + instantiated[0] + allocated[0] != 8 { return result.err(failure { message: "explicit arrays" }) }
    ints := int[]()
    ints.push(2)
    items := item[]()
    items.push(item { value: ints[0] })
    returned := create()
    nested := records.collection { values: returned }
    selected := first(nested.values)
    snapshot := returned[0]
    snapshot.amount = 0
    if returned[0].amount != 40 { return result.err(failure { message: "aliased read" }) }
    if first(items).value != 2 { return result.err(failure { message: "wrong generic element" }) }
    return result.ok(selected.amount + option_length(chosen()))
}
func main() int { answer, error := compute(); return answer + len(error.message) }
S
for order in first second; do
    sources=("$work/library.s" "$work/foreign.s")
    if [ "$order" = second ]; then sources=("$work/foreign.s" "$work/library.s"); fi
    "$root/bin/s_seed" --compile-native-unit "$work/$order.ir" "$root/src/result/result.s" "$root/src/option/option.s" "${sources[@]}" "$work/main.s"
    S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/$order.ir" "$work/$order"
    status=0; timeout 15 "$work/$order" || status=$?; test "$status" -eq 42
done
echo 'array constructors, indexing, records, imported returns and generic elements: PASS'
cat > "$work/pattern.s" <<'S'
package main
import "records"
import "std.result"
struct failure { string message }
enum parcel { values(records.collection), empty }
func from_pattern(parcel input) result[int,failure] {
    switch input {
        parcel.values(value): result.ok(value.values[0].amount),
        parcel.empty: result.err(failure { message: "empty" }),
    }
}
func main() int { return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/pattern.ir" "$root/src/result/result.s" "$work/library.s" "$work/pattern.s"
echo 'array field typing inside a concrete enum pattern: PASS (source validation)'

python3 - "$work" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
cases={
 'string_index':'func main() int { values := int[](); values.push(42); return values["0"] }',
 'bool_index':'func main() int { values := int[](); values.push(42); return values[true] }',
 'float_index':'func main() int { values := int[](); values.push(42); return values[0.0] }',
 'borrow_element':'func bump(records.cell* target) () { target.amount = 1 }\nfunc main() int { values := records.cell[](); values.push(records.cell { amount: 42 }); bump(values[0]); return 42 }',
 'intrinsic_arity':'func main() int { values := host_args(1); return 42 }',
 'intrinsic_shadow':'func host_args() int { return 42 }\nfunc main() int { return host_args()[0] }',
 'non_array':'func main() int { value := 42; return value[0] }',
 'wrong_element':'func require_string(string value) int { return 42 }\nfunc main() int { values := records.cell[](); values.push(records.cell { amount: 42 }); value := values[0]; return require_string(value.amount) }',
}
for name,body in cases.items(): (p/(name+'.s')).write_text('package main\nimport "records"\n'+body+'\n')
PY
printf 'preserve\n' > "$work/output"
cp "$work/output" "$work/saved"
for name in string_index bool_index float_index non_array wrong_element borrow_element intrinsic_arity intrinsic_shadow; do
    if "$root/bin/s_seed" --compile-native-unit "$work/output" "$root/src/result/result.s" "$work/library.s" "$work/$name.s" > "$work/$name.log" 2>&1; then
        echo "invalid array index accepted: $name" >&2; exit 1
    fi
    cmp "$work/output" "$work/saved"
done
echo 'array index operand and element type rejection: PASS'

for name in string_index bool_index float_index non_array wrong_element intrinsic_arity intrinsic_shadow; do
    if "$root/bin/s_seed" --compile-native-unit "$work/output" "$work/library.s" "$work/$name.s" > "$work/semantic-$name.log" 2>&1; then
        echo "semantic checker accepted invalid array index: $name" >&2; exit 1
    fi
    cmp "$work/output" "$work/saved"
done
echo 'ordinary semantic array index validation: PASS'

# The compatibility source checker must retain array fields after unwrap as well.
cat > "$work/unwrap.s" <<'S'
package main
struct data { int[] items }
func produce() (data,string) { return data { items: [42] }, "" }
func main() int { value := produce().unwrap(); return value.items[0] }
S
"$root/bin/s_seed" --compile-unit "$work/unwrap.ir" "$work/unwrap.s"
sed 's/return value.items\[0\]/return require_string(value.items[0])/' "$work/unwrap.s" > "$work/wrong-unwrap.s"
printf '\nfunc require_string(string value) int { return 42 }\n' >> "$work/wrong-unwrap.s"
if "$root/bin/s_seed" --compile-unit "$work/output" "$work/wrong-unwrap.s" > "$work/wrong-unwrap.log" 2>&1; then
    echo 'lost array element type after unwrap' >&2; exit 1
fi
grep -q 'type mismatch' "$work/wrong-unwrap.log"
cmp "$work/output" "$work/saved"
echo 'source checker retains array element type through tuple unwrap: PASS'

# A foreign same-leaf box type must not acquire the std box payload contract.
cat > "$work/custom-box.s" <<'S'
package foreign
struct box[t] { t value }
func (box[t] self) unwrap() string { return "custom" }
S
cat > "$work/custom-client.s" <<'S'
package main
import "foreign"
func require_string(string value) int { return 42 }
func check(foreign.box[int] value) int { return require_string(value.unwrap()) }
func main() int { return 42 }
S
"$root/bin/s_seed" --compile-unit "$work/custom-box.ir" "$work/custom-box.s" "$work/custom-client.s"
echo 'foreign box name does not select the std payload type: PASS (source validation)'
