#!/bin/bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-compile-pipeline-harness.XXXXXXXX")
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin"
cat > "$work/bin/make" <<'MAKE'
#!/bin/bash
case "${1:-}" in
  canonical-parser-closure-check)
    exit 0
    ;;
  canonical-name-resolution-check)
    echo "canonical-name-resolution-check"
    echo "  stage5-name-resolution  = PENDING_IMPLEMENTATION"
    exit 0
    ;;
  *)
    exit 2
    ;;
esac
MAKE
chmod +x "$work/bin/make"

output="$work/output.txt"
set +e
(
  cd "$work"
  PATH="$work/bin:$PATH" S_SOURCE_ROOT="$work" bash "$repo_root/scripts/compile-pipeline-check.sh"
) >"$output" 2>&1
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "expected compile-pipeline-check to fail when Stage 5 is placeholder" >&2
  cat "$output" >&2
  exit 1
fi

if grep -q 'ALL STAGES PASSED\|COMPLETE (all' "$output"; then
  echo "pipeline reported completion despite placeholder or skipped gates" >&2
  cat "$output" >&2
  exit 1
fi

grep -q 'Name/Import Resolution.*PLACEHOLDER.*UNPROVEN' "$output"
grep -q 'CURRENT BLOCKER = Stage 5 Name/Import Resolution' "$output"
grep -q 'PIPELINE COMPLETE = NO' "$output"

echo "compile pipeline harness regression passed"
