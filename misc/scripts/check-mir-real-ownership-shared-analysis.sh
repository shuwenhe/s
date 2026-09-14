#!/bin/bash
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
analysis_file="$root/src/cmd/compile/internal/ownership/analysis.s"
mir_file="$root/src/cmd/compile/internal/mir.s"
compiler_file="$root/src/cmd/compile/compiler.s"

require_text() {
    file=$1
    needle=$2
    label=$3
    if ! grep -Fq "$needle" "$file"; then
        echo "mir real ownership shared analysis: missing $label" >&2
        echo "  file: ${file#$root/}" >&2
        echo "  text: $needle" >&2
        exit 1
    fi
}

reject_text() {
    file=$1
    needle=$2
    label=$3
    if grep -Fq "$needle" "$file"; then
        echo "mir real ownership shared analysis: unexpected $label" >&2
        echo "  file: ${file#$root/}" >&2
        echo "  text: $needle" >&2
        exit 1
    fi
}

# Architecture Gate (C.2.4b.1): Sole Solver Authority in compiler.s
# After Phase B2: Single analyze_ownership_liveness() implementation in compiler.s
# analysis.s: type definitions only (no solver implementation)

require_text "$analysis_file" 'package compile.internal.ownership.analysis' 'analysis package'
require_text "$analysis_file" 'struct ownership_analysis_input {' 'shared input type'
require_text "$analysis_file" 'struct ownership_analysis {' 'shared output type'

# CRITICAL: No solver in analysis.s (Phase B2 architecture decision)
reject_text "$analysis_file" 'func analyze_ownership_liveness' 'analysis.s must NOT have solver'

# MIR imports solver from compiler.s (via analysis.s package namespace)
require_text "$mir_file" '"compile.internal.ownership.analysis"' 'MIR imports input type'

require_text "$mir_file" 'func build_ownership_analysis_input_from_mir' 'MIR fact extractor'
require_text "$mir_file" 'func dump_ownership_shadow_from_mir' 'MIR shadow diagnostic'
require_text "$mir_file" 'compile.internal.ownership.analysis.analyze_ownership_liveness(facts.input)' 'MIR shadow invokes solver'

# No duplicate solver in mir.s (Phase B2 architecture decision)
reject_text "$mir_file" 'while changed' 'MIR must not duplicate solver loop'

# Sole solver authority in compiler.s
require_text "$compiler_file" 'func analyze_ownership_liveness(ownership_analysis_input input) ownership_analysis' 'compiler.s sole solver'

echo "mir-real-ownership-shared-analysis-check: ok"
