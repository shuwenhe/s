#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
seed=${S_SEED_COMPILER:-"$root/bin/s_seed"}
work=$(mktemp -d /tmp/s-native-record-parameter-order.XXXXXX)
trap 'rm -rf "$work"' EXIT

compile_and_run() {
    local name=$1
    shift
    "$seed" --compile-native-unit "$work/$name.ir" "$@"
    S_SOURCE_ROOT="$root" "$seed" --emit-standalone-amd64 "$work/$name.ir" "$work/$name"
    local status=0
    "$work/$name" || status=$?
    if [ "$status" -ne 42 ]; then
        echo "$name returned $status, want 42" >&2
        exit 1
    fi
}

# Both syntaxes have the same tokens, so whitespace cannot choose the record
# referent. The function appears before its record declaration intentionally.
index=0
for parameter in 'target* cell' 'target * cell' 'cell* target' 'cell * target'; do
    cat > "$work/order.s" <<S
package main
func set($parameter, int number) { target.number = number }
struct cell { int number }
func main() int { value := cell { number: 1 }; set(value, 42); return value.number }
S
    compile_and_run "order-$index" "$work/order.s"
    index=$((index + 1))
done

# A variable's spelling may name a record in another package. Its signature
# must resolve inside the function's package, even when short names collide.
cat > "$work/alpha.s" <<'S'
package alpha
struct cell { int number }
func alpha_set(target* cell) { target.number = 40 }
S
cat > "$work/beta.s" <<'S'
package beta
struct cell { string number }
struct target { int* owner }
func beta_set(cell * target) { target.number = "ok" }
S
cat > "$work/main.s" <<'S'
package main
import "alpha"
import "beta"
func main() int {
    first := alpha.cell {}
    second := beta.cell {}
    alpha_set(first)
    beta_set(second)
    return first.number + len(second.number)
}
S
compile_and_run packages "$work/alpha.s" "$work/beta.s" "$work/main.s"
compile_and_run packages-reversed "$work/beta.s" "$work/alpha.s" "$work/main.s"

# Qualified names keep their declared identity when a local record shadows
# the imported short name. A borrowed alpha.cell cannot receive main.cell.
cat > "$work/shadow.s" <<'S'
package main
import "alpha"
struct cell { int number }
func set(target* alpha.cell) { target.number = 42 }
func main() int { value := cell {}; set(value); return value.number }
S
printf 'preserve artifact\n' > "$work/output"
cp "$work/output" "$work/saved"
if "$seed" --compile-native-unit "$work/output" "$work/alpha.s" "$work/shadow.s" > "$work/shadow.log" 2>&1; then
    echo 'borrow signature accepted a shadowing record from another package' >&2
    exit 1
fi
grep -q 'unproven' "$work/shadow.log"
cmp "$work/output" "$work/saved"

# Same-named records in different packages must not erase resource ownership.
cat > "$work/owner.s" <<'S'
package owners
struct cell { int* owner }
S
cat > "$work/owner-main.s" <<'S'
package main
import "owners"
struct cell { int number }
func set(target* owners.cell) { return }
func main() int { value := owners.cell {}; set(value); return 42 }
S
if "$seed" --compile-native-unit "$work/output" "$work/owner.s" "$work/owner-main.s" > "$work/owner.log" 2>&1; then
    echo 'borrow signature accepted a resource-bearing imported record' >&2
    exit 1
fi
grep -Eq 'unproven|unsupported_owner' "$work/owner.log"
cmp "$work/output" "$work/saved"

# A real non-record type cannot become a parameter name just because the
# other identifier also names a record. Its unsupported pointer must reject.
for referent in int choice; do
    cat > "$work/non-record.s" <<S
package main
struct cell { int number }
enum choice { zero, one }
func invalid($referent* cell) { return }
func main() int { return 42 }
S
    if "$seed" --compile-native-unit "$work/output" "$work/non-record.s" > "$work/non-record.log" 2>&1; then
        echo "non-record pointer changed into a record borrow: $referent" >&2
        exit 1
    fi
    grep -q 'unproven' "$work/non-record.log"
    cmp "$work/output" "$work/saved"
done

# Readable user calls still require rejection inside a borrowed call's
# argument list, including nested calls and names that shadow intrinsics.
for name in user-call nested-call intrinsic-call write shadowed-len; do
    case "$name" in
        user-call) argument='effect()' ;;
        nested-call) argument='len(to_string(effect()))' ;;
        intrinsic-call) argument='len("answer") * 7' ;;
        write) argument='(value.number = 42)' ;;
        shadowed-len) argument='len(42)' ;;
    esac
    cat > "$work/$name.s" <<S
package main
struct cell { int number }
func effect() int { return 42 }
func set(target* cell, int number) { target.number = number }
S
    if [ "$name" = shadowed-len ]; then
        printf 'func len(int count) int { return count }\n' >> "$work/$name.s"
    fi
    printf 'func main() int { value := cell {}; set(value, %s); return value.number }\n' "$argument" >> "$work/$name.s"
    if "$seed" --compile-native-unit "$work/output" "$work/$name.s" > "$work/$name.log" 2>&1; then
        echo "effectful borrowed argument accepted: $name" >&2
        exit 1
    fi
    grep -q 'unproven' "$work/$name.log"
    cmp "$work/output" "$work/saved"
done
echo 'native record parameter orders, package identity and ownership rejection: PASS'
