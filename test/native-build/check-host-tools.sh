#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-host-tools.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/tool with spaces" <<'TOOL'
#!/bin/sh
case "$1" in
  success) exit 0 ;;
  signal) kill -TERM "$$" ;;
  *)
    [ "$#" -eq 3 ] && [ "$1" = 'a b' ] && [ "$2" = '$(touch injected)' ] && [ "$3" = "quote'\";" ] || exit 99
    exit 7 ;;
esac
TOOL
chmod +x "$work/tool with spaces"
timeout 30s "$root/bin/s_seed" --compile-unit "$work/test.ir" "$root/test/native-build/host_tools.s"
timeout 30s "$root/bin/s_seed" --emit-bin "$work/test.ir" "$work/test"
(cd "$work" && timeout 10s "$work/test" "$work/tool with spaces" "$work")
test ! -e "$work/injected"
printf '%s\n' 'Host argv execution, status and file installation PASS'
