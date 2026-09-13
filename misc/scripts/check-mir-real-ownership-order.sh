#!/bin/bash
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
test_file="$root/src/cmd/compile/internal/tests/test_mir.s"
fixture="$root/src/cmd/compile/internal/tests/fixtures/real_mir_ref_flow.s"

require_text() {
    file=$1
    needle=$2
    label=$3
    if ! grep -Fq -- "$needle" "$file"; then
        echo "mir-real-ownership-order-check: missing $label" >&2
        echo "  file: ${file#$root/}" >&2
        echo "  text: $needle" >&2
        exit 1
    fi
}

# Verify fixture has interleaved regular and ownership statements
require_text "$fixture" 'reader := &owner' 'borrow statement in fixture'
require_text "$fixture" 'y := 100' 'interleaved regular statement 1'
require_text "$fixture" 'other := reader' 'ref assign statement'
require_text "$fixture" 'z := y + 1' 'interleaved regular statement 2'
require_text "$fixture" 'x := *other' 'ref use statement'

# Verify test function exists and uses real pipeline
require_text "$test_file" 'test_real_mir_semantic_order' 'semantic order test function'
require_text "$test_file" 'read_source' 'real source reading'
require_text "$test_file" 'parse_source' 'real parsing'
require_text "$test_file" 'lower_main_to_mir' 'real lowering'
require_text "$test_file" 'build_mir_point_map' 'canonical point mapping'

# Verify test validates relative ordering, not absolute P0/P1/P2
require_text "$test_file" 'borrow_stmt < ref_assign_stmt' 'relative statement order validation'
require_text "$test_file" 'ref_assign_stmt < ref_use_stmt' 'sequential ownership order'
require_text "$test_file" 'borrow_point < ref_assign_point' 'canonical point relative order'
require_text "$test_file" 'ref_assign_point < ref_use_point' 'canonical point sequence'

# Verify same basic block assumption (Phase 1)
# Implementation: if borrow_block != ref_assign_block || ... return 1
require_text "$test_file" 'borrow_block != ref_assign_block' 'same BB validation (phase 1)'

echo "mir-real-ownership-order-check: ok"
