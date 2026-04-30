#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

pkgs=(
  fmt
  errors
  strings
  strconv
  bytes
  io
  os
  path/filepath
  time
  context
  sync
  sync/atomic
  net
  net/http
  net/url
  encoding/json
  testing
  log
  runtime/pprof
  compress/gzip
)

missing=0
for p in "${pkgs[@]}"; do
  dir="$ROOT_DIR/src/$p"
  if [[ -d "$dir" ]]; then
    count=$(find "$dir" -type f -name '*.s' | wc -l)
    echo "ok: src/$p (s files: $count)"
  else
    echo "missing: src/$p"
    missing=$((missing + 1))
  fi
done

echo ""
echo "toolchain smoke:"
(
  cd "$ROOT_DIR"
  s fmt src >/tmp/s_fmt_top20.log 2>&1 || true
  s lint src >/tmp/s_lint_top20.log 2>&1 || true
  s test >/tmp/s_test_smoke_top20.log 2>&1 || true
)

echo "- fmt log: /tmp/s_fmt_top20.log"
echo "- lint log: /tmp/s_lint_top20.log"
echo "- test log: /tmp/s_test_smoke_top20.log"

if [[ $missing -ne 0 ]]; then
  echo "summary: missing package roots = $missing"
  exit 1
fi

echo "summary: package roots present"
