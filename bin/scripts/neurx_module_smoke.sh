#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
S_BIN="${S_BIN:-$ROOT_DIR/bin/s}"
NEURX_ROOT="${NEURX_ROOT:-$(cd "$ROOT_DIR/../neurx" 2>/dev/null && pwd || true)}"

if [[ ! -x "$S_BIN" ]]; then
  echo "error: s wrapper not executable: $S_BIN" >&2
  exit 1
fi

if [[ -z "$NEURX_ROOT" || ! -d "$NEURX_ROOT" ]]; then
  echo "error: neurx repo not found (set NEURX_ROOT)" >&2
  exit 1
fi

echo "neurx smoke: root=$NEURX_ROOT"

"$S_BIN" mod index "$NEURX_ROOT"
INDEX="$NEURX_ROOT/build/s-package-index.tsv"

assert_index() {
  local pkg="$1"
  local rel="$2"
  awk -F '\t' -v pkg="$pkg" -v rel="$rel" '
    $1 == pkg && $2 == rel { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$INDEX" || {
    echo "fail: expected index entry: $pkg -> $rel" >&2
    exit 1
  }
  echo "ok: index $pkg -> $rel"
}

assert_index "neurx.agent.runtime" "agent/runtime.s"
assert_index "neurx.planner" "task/planner.s"
assert_index "neurx.agent.code_agent" "agent/code_agent.s"
assert_index "neurx.runtime.io" "runtime/io/io.s"

assert_resolve() {
  local module="$1"
  local expected_suffix="$2"
  local resolved
  resolved="$(cd "$NEURX_ROOT" && S_PROJECT_ROOT="$NEURX_ROOT" "$S_BIN" mod resolve "$module")"
  if [[ "$resolved" != *"$expected_suffix" ]]; then
    echo "fail: mod resolve $module -> $resolved (expected *$expected_suffix*)" >&2
    exit 1
  fi
  echo "ok: resolve $module -> $resolved"
}

assert_resolve "neurx.agent.runtime" "agent/runtime.s"
assert_resolve "neurx.planner" "task/planner.s"
assert_resolve "neurx.runtime.io" "runtime/io/io.s"

echo "neurx module smoke: PASS"
