#!/usr/bin/env bash
# ci-core.sh — clean-room self-host acceptance entrypoint for CI.
#
# Installs the exact host-tool set the acceptance pipeline requires, then runs
# the audited clean-room controller (misc/scripts/cleanroom-selfhost.py). The
# controller builds every bootstrap stage FRESH from the frozen revision (C Seed
# -> Stage1 -> Stage2 -> Stage3), verifies byte-for-byte convergence, and runs
# the full production regression. It reuses no cached or prebuilt compiler
# artifacts, so the result is a genuinely independent build.
#
# Usage: ci-core.sh <frozen-revision> [output-dir]
set -euo pipefail

REVISION="${1:-${CI_FROZEN_REVISION:-}}"
OUTDIR="${2:-/tmp/cleanroom-ci}"
if [ -z "${REVISION}" ]; then
  echo "ci-core: missing frozen revision (pass as arg1 or CI_FROZEN_REVISION)" >&2
  exit 2
fi

# repo root = two levels up from misc/scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "=== ci-core: repository=${REPO} revision=${REVISION} out=${OUTDIR} ==="

echo "=== installing required host tools ==="
# ripgrep (rg) is REQUIRED by the production regression suite
# (test/native-bootstrap-diagnostic/*.sh, 180+ invocations). The controller
# fails loudly if it is missing.
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
  git gcc make binutils strace time bash python3 python3-pip \
  ripgrep file

echo "=== verifying required tools ==="
for t in git gcc make as ld strace time bash python3 rg nm objdump readelf sha256sum cmp awk sed grep file timeout strings; do
  if ! command -v "$t" >/dev/null 2>&1; then
    echo "ci-core: required tool missing: $t" >&2
    exit 1
  fi
done
echo "all required tools present"

# Deterministic, isolated environment for the controller.
export PATH="/usr/bin:/bin"
unset LD_PRELOAD S_BOOTSTRAP_RUNNER S_SOURCE_ROOT S_CLOSURE_MODE CC CFLAGS MAKEFLAGS GIT_CONFIG_* || true

echo "=== running clean-room controller ==="
python3 "${REPO}/misc/scripts/cleanroom-selfhost.py" \
  --repository "${REPO}" \
  --revision "${REVISION}" \
  --output "${OUTDIR}" \
  --mode full

echo "=== ci-core: controller finished with status $? ==="
