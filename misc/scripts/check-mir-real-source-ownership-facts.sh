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
        echo "mir real source ownership facts: missing $label" >&2
        echo "  file: ${file#$root/}" >&2
        echo "  text: $needle" >&2
        exit 1
    fi
}

require_not_text() {
    file=$1
    needle=$2
    label=$3
    # Only check in the test function itself, not comments or helper functions
    func_start=$(grep -n "^func test_real_mir_source_ownership_facts" "$file" | cut -d: -f1)
    func_end=$(tail -n +$func_start "$file" | grep -n "^func " | tail -n +2 | head -n 1 | cut -d: -f1)
    if [ -z "$func_end" ]; then
        func_end=$(wc -l < "$file")
    else
        func_end=$((func_start + func_end - 2))
    fi
    func_body=$(sed -n "${func_start},${func_end}p" "$file")
    if echo "$func_body" | grep -Fq -- "$needle"; then
        echo "mir real source ownership facts: unexpected $label" >&2
        echo "  file: ${file#$root/}" >&2
        echo "  text: $needle" >&2
        exit 1
    fi
}

# Check fixture exists and has correct semantics
require_text "$fixture" 'reader := &owner' 'borrow assignment in fixture'
require_text "$fixture" 'other := reader' 'ref assignment in fixture'
require_text "$fixture" 'x := *other' 'ref use in fixture'

# Check test can parse real source
require_text "$test_file" 'test_real_mir_source_ownership_facts' 'real source test function'
require_text "$test_file" 'real_mir_ref_flow.s' 'fixture path reference'

# Check test extracts facts (not solver output)
require_text "$test_file" 'build_ownership_facts_from_mir' 'facts extraction call'
require_text "$test_file" 'PointCount' 'point count in facts dump'
require_text "$test_file" 'Ref' 'ref in facts dump'
require_text "$test_file" 'LoanLivePoints' 'forbidden solver output (sanity check)'

# Verify no solver invocation (facts-only in real test function)
require_not_text "$test_file" 'analyze_ownership_liveness' 'no solver invocation in facts test'
require_not_text "$test_file" 'dump_ownership_shadow_from_mir' 'no shadow call in facts test'

echo "mir-real-source-ownership-facts-check: ok"

