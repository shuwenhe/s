#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-hosted-program.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/cli.s" <<'S'
package main
func main() int {
    args := host_args()
    if len(args) == 4 && args[1] == "--emit-bin" { return 23 }
    if len(args) == 4 && args[1] == "--emit-aot" { return 24 }
    return 25
}
S
"$root/bin/s_seed" "$work/cli.s" "$work/cli.ir"
"$root/bin/s_seed" --emit-hosted-program "$work/cli.ir" "$work/cli"
for pair in '--emit-bin 23' '--emit-aot 24' '--compile-unit 25'; do
    read -r option wanted <<< "$pair"
    status=0
    "$work/cli" "$option" nonexistent-input "$work/output" || status=$?
    test "$status" -eq "$wanted"
    test ! -e "$work/output"
done
# Hosted diagnostics must never be accepted as native self-hosting evidence.
if sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/cli" > "$work/verify.log" 2>&1; then
    echo 'hosted executable accepted as true selfhost' >&2; exit 1
fi
echo 'hosted program CLI dispatch: PASS'
