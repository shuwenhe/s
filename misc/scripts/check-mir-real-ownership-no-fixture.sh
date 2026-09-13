#!/bin/bash
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

# Step 7 Gate: Verify real source tests are fixture-free
# 
# Legitimate: Synthetic MIR unit tests with hard-coded expectations (fact_graph)
# Forbidden: Real source tests using hard-coded fixture values
#
# The key: Real source tests should only:
#  1. Read real .s file
#  2. Lower through MIR
#  3. Extract facts
#  4. Verify structure (no hard-coded expected values)

test_file="$root/src/cmd/compile/internal/tests/test_mir.s"
mir_file="$root/src/cmd/compile/internal/mir.s"

# Step 7a: Verify synthetic MIR test exists (unit test baseline)
if ! grep -q "fact_graph :=" "$test_file"; then
    echo "mir-real-ownership-no-fixture-check: missing synthetic MIR test baseline" >&2
    exit 1
fi

# Step 7b: Verify real source tests exist
if ! grep -q "test_real_mir_source_ownership_facts\|test_real_mir_semantic_order" "$test_file"; then
    echo "mir-real-ownership-no-fixture-check: missing real source tests" >&2
    exit 1
fi

# Step 7c: Verify real source tests read files (not hard-coded graphs)
if ! grep -q "read_source" "$test_file"; then
    echo "mir-real-ownership-no-fixture-check: real source tests don't use read_source" >&2
    exit 1
fi

# Step 7d: Verify dump_ownership_shadow_from_mir calls solver, not hard-coded
if grep -q "dump_ownership_shadow_from_mir.*{" "$mir_file" && \
   grep -A 5 "dump_ownership_shadow_from_mir" "$mir_file" | grep -q "analyze_ownership_liveness"; then
    # Good: shadow calls solver
    :
else
    echo "mir-real-ownership-no-fixture-check: shadow must call solver" >&2
    exit 1
fi

# Step 7e: Verify no hard-coded ownership facts created in real source path
# Check: no synthetic mir_statement construction in real source tests
grep_result=$(grep -n "real_mir_source_ownership_facts\|real_mir_semantic_order" "$test_file" | head -2 | cut -d: -f1 | tail -1)
if [ -n "$grep_result" ]; then
    # Get the function and check its body for synthetic statement construction
    func_line=$(grep -n "^func test_real_mir_" "$test_file" | grep -E "(source_ownership_facts|semantic_order)" | head -1 | cut -d: -f1)
    next_func=$(tail -n +$((func_line + 1)) "$test_file" | grep -n "^func " | head -1 | cut -d: -f1)
    
    if [ -n "$next_func" ]; then
        end=$((func_line + next_func - 2))
    else
        end=$(wc -l < "$test_file")
    fi
    
    func_body=$(sed -n "${func_line},${end}p" "$test_file")
    
    # Forbidden: mir_statement::borrow construction (not pattern matching) in real tests
    if echo "$func_body" | grep -E "mir_statement::borrow\([^_]" > /dev/null; then
        echo "mir-real-ownership-no-fixture-check: real source test has synthetic borrow construction" >&2
        exit 1
    fi
fi

echo "mir-real-ownership-no-fixture-check: ok"




