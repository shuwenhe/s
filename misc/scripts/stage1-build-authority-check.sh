#!/bin/sh
set -eu

root=${S_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
report=${STAGE1_BUILD_AUTHORITY_REPORT:-"$root/.bootstrap/modular/stage1-build-authority-report.txt"}

mkdir -p "$(dirname -- "$report")"

stage0="$root/src/cmd/compile/stage0/stage0.c"
modular_main="$root/src/cmd/compile/modular_build_main.s"
backend="$root/src/cmd/compile/internal/backend_elf64.s"
syntax="$root/src/cmd/compile/internal/syntax/syntax.s"
semantic="$root/src/cmd/compile/internal/semantic.s"
mono="$root/src/cmd/compile/internal/mono/monomorphization.s"
ir_lower="$root/src/cmd/compile/internal/ir/lower.s"

current_build_handler=UNKNOWN
if rg -q 'return bootstrap_subset_build\(argv\[2\], argv\[4\]\)' "$stage0"; then
    current_build_handler="$stage0:161 -> bootstrap_subset_build"
fi

canonical_build_candidate=MISSING
if rg -q 'return compile\.internal\.backend_elf64\.build\(args\[2\], args\[4\], "", false\)' "$modular_main"; then
    canonical_build_candidate="$modular_main:46 -> compile.internal.backend_elf64.build(args[2], args[4], \"\", false)"
fi

canonical_parser_entry=MISSING
if rg -q 'compile\.internal\.syntax\.parse_source\(source\)' "$backend"; then
    canonical_parser_entry="$backend:2493 -> compile.internal.syntax.parse_source(source)"
fi

semantic_entry=MISSING
if rg -q 'compile\.internal\.semantic\.check_source_file\(combined, source\)' "$backend"; then
    semantic_entry="$backend:2505 -> compile.internal.semantic.check_source_file(combined, source)"
fi

mono_entry=MISSING
if rg -q 'compile\.internal\.mono\.monomorphize_file\(combined\)' "$backend"; then
    mono_entry="$backend:2509 -> compile.internal.mono.monomorphize_file(combined)"
fi

mir_entry=MISSING
if rg -q 'compile\.internal\.ir\.lower\.lower_main_to_mir\(parsed\)' "$backend"; then
    mir_entry="$backend:298 -> compile.internal.ir.lower.lower_main_to_mir(parsed)"
fi

backend_entry=MISSING
if rg -q '^func build\(string path, string output, string ssa_margin_override, bool nostdlib\) int' "$backend"; then
    backend_entry="$backend:278 -> func build(path, output, ssa_margin_override, nostdlib)"
fi

parser_definition=MISSING
if rg -q '^func parse_source\(string source\)' "$syntax"; then
    parser_definition="$syntax:32 -> func parse_source"
fi

semantic_definition=MISSING
if rg -q '^func check_source_file\(source_file file, string source\)' "$semantic"; then
    semantic_definition="$semantic:257 -> func check_source_file"
fi

mono_definition=MISSING
if rg -q '^func monomorphize_file\(source_file file\)' "$mono"; then
    mono_definition="$mono:191 -> func monomorphize_file"
fi

ir_definition=MISSING
if rg -q '^func lower_main_to_mir\(source_file src\)' "$ir_lower"; then
    ir_definition="$ir_lower:333 -> func lower_main_to_mir"
fi

replacement_edge=MISSING
missing_capability=NONE
if [ "$canonical_build_candidate" != MISSING ] && [ "$backend_entry" != MISSING ] && \
   [ "$canonical_parser_entry" != MISSING ] && [ "$semantic_entry" != MISSING ] && \
   [ "$mono_entry" != MISSING ] && [ "$mir_entry" != MISSING ]; then
    replacement_edge='stage1 build -> modular_build_main.build -> compile.internal.backend_elf64.build'
else
    missing_capability=canonical-build-chain-incomplete
fi

verdict=NOT_PROVEN
if [ "$current_build_handler" != UNKNOWN ] && [ "$replacement_edge" != MISSING ] && [ "$missing_capability" = NONE ]; then
    verdict=REPLACEMENT_EDGE_IDENTIFIED
fi

{
    echo "stage1-build-authority-check"
    echo "current-build-handler=$current_build_handler"
    echo "canonical-build-candidate=$canonical_build_candidate"
    echo "backend-entry=$backend_entry"
    echo "canonical-parser-entry=$canonical_parser_entry"
    echo "canonical-parser-definition=$parser_definition"
    echo "semantic-entry=$semantic_entry"
    echo "semantic-definition=$semantic_definition"
    echo "mono-entry=$mono_entry"
    echo "mono-definition=$mono_definition"
    echo "mir-entry=$mir_entry"
    echo "mir-definition=$ir_definition"
    echo "replacement-edge=$replacement_edge"
    echo "missing-capability=$missing_capability"
    echo "stage1-build-authority=$verdict"
} >"$report"

cat "$report"

if [ "$verdict" != REPLACEMENT_EDGE_IDENTIFIED ]; then
    exit 1
fi
