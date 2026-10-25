#!/usr/bin/env bash
set -euo pipefail
exec bash "$(dirname "$0")/native-artifact-gate.sh" 20 "${1:-${S_SOURCE_ROOT:-.}}"
