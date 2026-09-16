#!/bin/bash

# Regression gate: baseline probe tests before implementation

echo "=== PROBE BASELINE TEST (before e0b.2e implementation) ==="
echo "Date: $(date)"
echo ""

mkdir -p /tmp/probe_results

PASS_COUNT=0
FAIL_COUNT=0

# Test probes 01-08
for i in {1..8}; do
    probe=$(ls misc/probes/probe_$(printf "%02d" $i)_*.s 2>/dev/null | head -1)
    
    if [ -z "$probe" ]; then
        continue
    fi
    
    name=$(basename "$probe")
    printf "%-40s" "Testing: $name"
    
    output=$(./bin/s_seed "$probe" /tmp/probe_results/$(basename $probe .s).ir 2>&1)
    exit_code=$?
    
    if echo "$output" | grep -q "^compiled.*->"; then
        echo "✅ PASS"
        PASS_COUNT=$((PASS_COUNT + 1))
    elif echo "$output" | grep -q "^error"; then
        error_line=$(echo "$output" | head -1)
        echo "❌ FAIL"
        echo "         $error_line"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    else
        echo "❓ UNKNOWN"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

echo ""
echo "=== SUMMARY ==="
echo "  PASS: $PASS_COUNT/8"
echo "  FAIL: $FAIL_COUNT/8"
