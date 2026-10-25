#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-pattern-payload-identity.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/syntax.s" <<'S'
package syntax
struct expr { string text }
struct assign_stmt { expr value }
S
cat > "$work/lower.s" <<'S'
package lower
struct expr_ir { int value }
struct assign_stmt { expr_ir value }
enum stmt_ir { assign(assign_stmt), empty }
func build() stmt_ir { return stmt_ir.assign(assign_stmt { value: expr_ir { value: 42 } }) }
func id[t](t value) t { return value }
func take(expr_ir input) int { return id(input.value) }
func inspect(stmt_ir input) int {
    switch input {
        stmt_ir.assign(item): take(item.value),
        stmt_ir.empty: 0,
    }
}
func main() int { return 42 }
S
for order in first second; do
    sources=("$work/syntax.s" "$work/lower.s")
    if [ "$order" = second ]; then sources=("$work/lower.s" "$work/syntax.s"); fi
    "$root/bin/s_seed" --compile-native-unit "$work/$order.ir" "${sources[@]}"
done
sed -e '/func id\[t\]/d' -e 's/return id(input.value)/return input.value/' -e 's/stmt_ir.assign(assign_stmt/stmt_ir.assign(lower.assign_stmt/' -e 's/value: expr_ir {/value: lower.expr_ir {/' "$work/lower.s" > "$work/ordinary.s"
"$root/bin/s_seed" --compile-native-unit "$work/ordinary.ir" "$work/syntax.s" "$work/ordinary.s"
# A payload whose declared field really is the foreign expression must fail.
sed 's/struct assign_stmt { expr_ir value }/struct assign_stmt { syntax.expr value }/' "$work/lower.s" > "$work/wrong.s"
printf 'preserve\n' > "$work/output"
cp "$work/output" "$work/saved"
if "$root/bin/s_seed" --compile-native-unit "$work/output" "$work/syntax.s" "$work/wrong.s" > "$work/wrong.log" 2>&1; then
    echo 'foreign payload field accepted as local expression' >&2; exit 1
fi
cmp "$work/output" "$work/saved"
grep -q 'type mismatch' "$work/wrong.log"
echo 'enum constructor and pattern payload keep their declaration package: PASS'
