#!/usr/bin/env bash
set -euo pipefail
exec bash "$(dirname "$0")/native-artifact-gate.sh" 21 "${1:-${S_SOURCE_ROOT:-.}}"
