#!/usr/bin/env bash
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

require_text "$analysis_file" 'package compile.internal.ownership.analysis' 'shared ownership analysis package'
require_text "$analysis_file" 'struct ownership_analysis_input {' 'shared analysis input type'
require_text "$analysis_file" 'struct ownership_analysis {' 'shared analysis output type'
require_text "$analysis_file" 'func analyze_ownership_liveness' 'shared liveness solver'
require_text "$mir_file" 'use compile.internal.ownership.analysis.ownership_analysis_input' 'MIR imports shared input type'
require_text "$mir_file" 'use compile.internal.ownership.analysis.analyze_ownership_liveness' 'MIR imports shared solver'
require_text "$mir_file" 'func build_ownership_analysis_input_from_mir(mir_graph graph, mir_point_map points) ownership_analysis_input' 'MIR extractor returns shared input'
require_text "$mir_file" 'func dump_ownership_shadow_from_mir' 'MIR shadow diagnostic client'
require_text "$mir_file" 'analysis := analyze_ownership_liveness(facts.input)' 'MIR shadow uses shared solver'
reject_text "$mir_file" 'while changed' 'MIR package duplicate fixed-point loop'
require_text "$compiler_file" 'func analyze_ownership_liveness(ownership_analysis_input input) ownership_analysis' 'monolithic diagnostic compatibility solver'

echo "mir-real-ownership-shared-analysis-check: ok"
