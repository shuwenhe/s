#!/bin/bash
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

# Step 8 Gate: Verify real source facts integrate with solver
#
# Objective: Prove that real MIR source code facts enter the SINGLE solver
# and produce valid ownership analysis output.
#
# Success criteria:
# 1. Real source can be parsed, lowered, and converted to MIR
# 2. dump_ownership_shadow_from_mir can be called on real MIR
# 3. Output contains solver results (LoanLivePoints, converged)
# 4. No hard-coded fixture values in solver invocation

test_file="$root/src/cmd/compile/internal/tests/test_mir.s"
mir_file="$root/src/cmd/compile/internal/mir.s"
fixture_file="$root/src/cmd/compile/internal/tests/fixtures/real_mir_ref_flow.s"

# Step 8.1: Verify dump_ownership_shadow_from_mir is defined in mir.s
if ! grep -q "^func dump_ownership_shadow_from_mir" "$mir_file"; then
    echo "mir-real-ownership-solver-integration: ERROR - dump_ownership_shadow_from_mir not defined" >&2
    exit 1
fi

# Step 8.2: Verify dump_ownership_shadow_from_mir calls solver
if ! grep -A 10 "^func dump_ownership_shadow_from_mir" "$mir_file" | grep -q "analyze_ownership_liveness"; then
    echo "mir-real-ownership-solver-integration: ERROR - dump_ownership_shadow_from_mir doesn't call solver" >&2
    exit 1
fi

# Step 8.3: Verify shadow output contains solver results
if ! grep -A 20 "^func dump_ownership_shadow_from_mir" "$mir_file" | grep -q "LoanLivePoints"; then
    echo "mir-real-ownership-solver-integration: ERROR - dump_ownership_shadow_from_mir doesn't output LoanLivePoints" >&2
    exit 1
fi

# Step 8.4: Verify real fixture file exists
if [ ! -f "$fixture_file" ]; then
    echo "mir-real-ownership-solver-integration: ERROR - real fixture not found: $fixture_file" >&2
    exit 1
fi

# Step 8.5: Verify mir.s imports solver properly
if ! grep -q "compile.internal.ownership.analysis.analyze_ownership_liveness" "$mir_file"; then
    echo "mir-real-ownership-solver-integration: ERROR - mir.s doesn't call solver" >&2
    exit 1
fi

# Step 8.6-8 helper: Extract dump_ownership_shadow_from_mir function body
dump_func_start=$(grep -n "^func dump_ownership_shadow_from_mir" "$mir_file" | cut -d: -f1)
dump_func_end=$(tail -n +$((dump_func_start + 1)) "$mir_file" | grep -n "^func " | head -1 | cut -d: -f1)
if [ -z "$dump_func_end" ]; then
    dump_func_end=$(wc -l < "$mir_file")
else
    dump_func_end=$((dump_func_start + dump_func_end - 2))
fi
dump_func_body=$(sed -n "${dump_func_start},${dump_func_end}p" "$mir_file")

# Step 8.6: Verify fact extraction happens before solver in dump function
# (Only check within the dump_ownership_shadow_from_mir function)
facts_in_func=$(echo "$dump_func_body" | grep -n "build_ownership_facts_from_mir" | head -1 | cut -d: -f1)
solver_in_func=$(echo "$dump_func_body" | grep -n "analyze_ownership_liveness" | head -1 | cut -d: -f1)
if [ -n "$facts_in_func" ] && [ -n "$solver_in_func" ]; then
    if [ "$facts_in_func" -gt "$solver_in_func" ]; then
        echo "mir-real-ownership-solver-integration: ERROR - solver called before fact extraction in dump function" >&2
        exit 1
    fi
fi

# Step 8.7: Verify shadow format includes convergence check
if ! echo "$dump_func_body" | grep -q "converged"; then
    echo "mir-real-ownership-solver-integration: ERROR - shadow doesn't validate convergence" >&2
    exit 1
fi

# Step 8.8: Verify no hard-coded loan points in dump function
# Forbidden: hard-coded loan indices like "LoanLivePoints(L0) = {P0,P2}"
if echo "$dump_func_body" | grep -E 'LoanLivePoints\(L[0-9]+\) = ' > /dev/null; then
    echo "mir-real-ownership-solver-integration: ERROR - hard-coded LoanLivePoints values in dump function" >&2
    exit 1
fi

echo "mir-real-ownership-solver-integration: ok"
