#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-bootstrap-gate.XXXXXX)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/repo/bin" "$work/repo/src/cmd/dist" "$work/repo/misc/scripts" "$work/out"
cp "$root/misc/scripts/verify_true_selfhost.sh" "$work/repo/misc/scripts/"
chmod +x "$work/repo/misc/scripts/verify_true_selfhost.sh"
cat > "$work/repo/src/cmd/dist/source_closure.sh" <<'SH'
#!/bin/sh
printf '%s\n' 'src/cmd/compile/main.s' > "$2"
SH
cat > "$work/repo/bin/s_seed" <<'SH'
#!/bin/sh
case "$1" in
    --compile-native-unit) printf 'SSEED-TARGET-V1\n' > "$2" ;;
    --emit-standalone-amd64|--emit-bin)
        printf '%s\n' "$1" >> "$S_TEST_SEED_CALLS"
        cp /bin/true "$3" ;;
    *) exit 99 ;;
esac
SH
chmod +x "$work/repo/bin/s_seed" "$work/repo/src/cmd/dist/source_closure.sh"
mkdir -p "$work/repo/src/cmd/compile"
printf 'package main\n' > "$work/repo/src/cmd/compile/main.s"
# A failed rerun must invalidate earlier success evidence.
touch "$work/out/.complete"
if S_SOURCE_ROOT="$work/repo" S_TEST_SEED_CALLS="$work/calls" \
    bash "$root/src/cmd/dist/native-bootstrap-no-manifest.sh" "$work/out" > "$work/log" 2>&1; then
    echo 'bootstrap accepted a dynamic stage1 and claimed convergence' >&2; exit 1
fi
cat "$work/log"
grep -q 'dynamic interpreter' "$work/log"
grep -qx -- '--emit-standalone-amd64' "$work/calls"
test ! -e "$work/out/stage2.ir"
test ! -e "$work/out/.complete"
echo 'native bootstrap rejects hosted stage1: PASS'
