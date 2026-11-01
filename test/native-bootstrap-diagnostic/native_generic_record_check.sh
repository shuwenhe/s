#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-generic-record.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo "generic artifacts: $work" >&2; fi' EXIT
cat > "$work/generic.s" <<'S'
package main
struct holder[t] { t value }
func wrap[t](t value) holder[t] {
    result := holder[t] { value: value }
    return result
}
func number(holder[int] value) int { return value.value }
func text(holder[string] value) int {
    if value.value == "copied" { return 2 }
    return 1
}
func main() int {
    first := holder[int] { value: 40 }
    second := wrap("copied")
    return number(first) + text(second)
}
S
"$root/bin/s_seed" --compile-native-unit "$work/generic.ir" "$work/generic.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/generic.ir" "$work/generic"
status=0; timeout 15 "$work/generic" || status=$?
test "$status" -eq 42
cat > "$work/prelude.s" <<'S'
package main
func main() int {
    first := box(40)
    second := box("ok")
    return first.value + len(second.value)
}
S
"$root/bin/s_seed" --compile-native-unit "$work/prelude.ir" "$root/src/prelude/prelude.s" "$work/prelude.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/prelude.ir" "$work/prelude"
status=0; timeout 15 "$work/prelude" || status=$?
test "$status" -eq 42
printf 'keep prior output\n' > "$work/output"
cp "$work/output" "$work/saved"
cat > "$work/wrong.s" <<'S'
package main
struct holder[t] { t value }
func take(holder[int] value) int { return value.value }
func main() int {
    value := holder[string] { value: "bad" }
    return take(value)
}
S
cat > "$work/owner.s" <<'S'
package main
struct holder[t] { t value }
struct resource { int* pointer }
func main() int { value := holder[resource] {}; return 42 }
S
for name in wrong owner; do
    if "$root/bin/s_seed" --compile-native-unit "$work/output" "$work/$name.s" > "$work/$name.log" 2>&1; then
        echo "invalid generic record accepted: $name" >&2; exit 1
    fi
    cmp "$work/output" "$work/saved"
done
grep -Eq 'type mismatch|argument.*type' "$work/wrong.log"
grep -Eq 'unsupported_owner|unproven' "$work/owner.log"
echo 'native generic record identities, factory inference and ownership: PASS'
cat > "$work/library.s" <<'S'
package lib
struct holder[t] { t value }
func wrap[t](t value) holder[t] { return holder[t] { value: value } }
S
cat > "$work/client.s" <<'S'
package main
use lib as l
func id[t](t value) t { return value }
func main() int {
    check := id(1 == 1)
    result := 0
    value := 42
    if check {
        for value in [40, 1, 2, 100] {
            if value == 1 { continue }
            if value == 100 { break }
            result = result + l.wrap(value).value
        }
    }
    return result + value - 42
}
S
"$root/bin/s_seed" --compile-native-unit "$work/alias.ir" "$work/library.s" "$work/client.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/alias.ir" "$work/alias"
status=0; timeout 15 "$work/alias" || status=$?
test "$status" -eq 42
cat > "$work/shadow.s" <<'S'
package main
func id[t](t value) t { return value }
func main() int { id := 0; return id(42) }
S
cat > "$work/unimported.s" <<'S'
package main
func main() int { return wrap(42).value }
S
cat > "$work/field.s" <<'S'
package main
struct holder[t] { t value }
func main() int { value := holder[int] { value: "bad" }; return 42 }
S
for name in shadow unimported field; do
    if "$root/bin/s_seed" --compile-native-unit "$work/output" "$work/library.s" "$work/$name.s" > "$work/$name.log" 2>&1; then
        echo "invalid generic resolution/layout accepted: $name" >&2; exit 1
    fi
    cmp "$work/output" "$work/saved"
done
# A forged producer must also be rejected independently before native tools.
sed 's/|value|int$/|value|string/' "$work/generic.ir" > "$work/forged.ir"
if S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/forged.ir" "$work/output" > "$work/forged.log" 2>&1; then
    echo 'generic field layout forgery accepted by native backend' >&2; exit 1
fi
cmp "$work/output" "$work/saved"
grep -Eq 'borrow|record' "$work/forged.log"
echo 'native generic lexical scope, inference and independent layout validation: PASS'
cat > "$work/method.s" <<'S'
package main
struct holder[t] { t value }
func (holder[t]* self) set(t value) { self.value = value }
func (holder[t] self) get() t { return self.value }
func main() int {
    item := holder[int] { value: 40 }
    snapshot := item
    item.set(42)
    return item.get() + snapshot.value - 40
}
S
"$root/bin/s_seed" --compile-native-unit "$work/method.ir" "$work/method.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/method.ir" "$work/method"
status=0; timeout 15 "$work/method" || status=$?
test "$status" -eq 42
cat > "$work/invalid-template.s" <<'S'
package main
func bad[t](t value) t { return missing }
func main() int { return 42 }
S
if "$root/bin/s_seed" --compile-native-unit "$work/output" "$work/invalid-template.s" > "$work/invalid-template.log" 2>&1; then
    echo 'unused generic template escaped source validation' >&2; exit 1
fi
cmp "$work/output" "$work/saved"
grep -q missing "$work/invalid-template.log"
if grep -Eq '^MOV\|[^|]*\.__type\|"(main|lib)\.holder"\|' "$work/generic.ir" "$work/alias.ir"; then
    echo 'abstract generic record lowered into executable IR' >&2; exit 1
fi
echo 'native generic receivers, value snapshots and abstract source validation: PASS'
