#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work="$root/.bootstrap/native-record-preflight"
mkdir -p "$work"
cat > "$work/owner.s" <<'S'
package main
struct resource { int* owner }
func main() int {
    if false { value := resource {}; return 1 }
    return 42
}
S
printf 'preserve output\n' > "$work/output.ir"
cp "$work/output.ir" "$work/saved"
if "$root/bin/s_seed" --compile-native-unit "$work/output.ir" "$work/owner.s" > "$work/reject.log" 2>&1; then
    echo 'unsupported owner accepted in dead branch' >&2; exit 1
fi
grep -q 'unsupported_owner' "$work/reject.log"
cmp "$work/output.ir" "$work/saved"
cat > "$work/forbidden-tool" <<'S'
#!/bin/sh
printf called >> "$S_TEST_TOOL_LOG"
exit 99
S
chmod +x "$work/forbidden-tool"
# External IR cannot bypass native ownership preflight.
"$root/bin/s_seed" --compile-unit "$work/owner.ir" "$work/owner.s"
if S_SOURCE_ROOT="$root" S_TEST_TOOL_LOG="$work/tools.log" \
    S_BOOTSTRAP_AS="$work/forbidden-tool" S_BOOTSTRAP_LD="$work/forbidden-tool" \
    "$root/bin/s_seed" --emit-standalone-amd64 "$work/owner.ir" "$work/output.ir" > "$work/ir-reject.log" 2>&1; then
    echo 'external IR bypassed owner preflight' >&2; exit 1
fi
grep -q 'unsupported_owner' "$work/ir-reject.log"
test ! -e "$work/tools.log"
cmp "$work/output.ir" "$work/saved"
cat > "$work/array-owner.s" <<'S'
package main
struct owner { int* pointer }
struct container { owner[] elements }
func main() int { value := container {}; return 42 }
S
if "$root/bin/s_seed" --compile-native-unit "$work/output.ir" "$work/array-owner.s" > "$work/array-reject.log" 2>&1; then
    echo 'array element owner escaped source preflight' >&2; exit 1
fi
grep -q 'unsupported_owner' "$work/array-reject.log"
cmp "$work/output.ir" "$work/saved"
cat > "$work/lib.s" <<'S'
package lib
struct owner { int* pointer }
struct wrapper { owner child }
S
cat > "$work/main.s" <<'S'
package main
func main() int {
    if false { x := lib.wrapper {}; return 1 }
    return 42
}
S
if "$root/bin/s_seed" --compile-native-unit "$work/output.ir" "$work/lib.s" "$work/main.s" > "$work/package-reject.log" 2>&1; then
    echo 'cross-package nested owner escaped source preflight' >&2; exit 1
fi
grep -q 'unsupported_owner' "$work/package-reject.log"
cmp "$work/output.ir" "$work/saved"
# Same bare name in the caller must not change imported field defaults.
cat > "$work/value-lib.s" <<'S'
package lib
struct child { int value }
struct wrapper { child nested }
S
cat > "$work/value-main.s" <<'S'
package main
struct child { string value }
func main() int {
    x := lib.wrapper {}
    if x.nested.value == 0 { return 42 }
    return 1
}
S
"$root/bin/s_seed" --compile-native-unit "$work/value.ir" "$work/value-lib.s" "$work/value-main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/value.ir" "$work/value"
status=0; "$work/value" || status=$?
test "$status" -eq 42
echo 'source and external IR owner preflight before output/tools: PASS'
