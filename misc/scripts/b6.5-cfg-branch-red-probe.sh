#!/usr/bin/env bash

# B6.5: CFG Branch Coverage - RED Probe
# 
# Strict execution framework:
# RED → classify first missing capability → fix only that → rerun → repeat
# 
# Three STOP conditions (do not continue to GREEN):
# 1. canonical doesn't have finalized CFG → canonical lowering gap
# 2. lowered-view must re-derive CFG → export-view gap  
# 3. serializer must construct true/false from if → semantic-authority leak
# 
# Otherwise: find and fix ONE capability at a time

set -e

S_SOURCE_ROOT="${S_SOURCE_ROOT:-.src}"
OUTPUT_FILE="${S_SOURCE_ROOT}/../../../.bootstrap/modular/b6.5-cfg-branch-red-probe.txt"

mkdir -p "$(dirname "$OUTPUT_FILE")"

{
    echo "=========================================="
    echo "B6.5: CFG Branch Coverage - RED Probe"
    echo "=========================================="
    echo ""
    echo "Test Case:"
    echo "  func choose(x int) int {"
    echo "    if x {"
    echo "      return 42"
    echo "    }"
    echo "    return 43"
    echo "  }"
    echo ""
    echo "  func main() int {"
    echo "    choose(1) → 42  [true path]"
    echo "    choose(0) → 43  [false path]"
    echo "  }"
    echo ""
    
    echo "════════════════════════════════════════"
    echo "PHASE 1: AUTHORITY CHECK (NON-NEGOTIABLE)"
    echo "════════════════════════════════════════"
    echo ""
    
    echo "Question: Who decides the CFG structure?"
    echo ""
    echo "Expected:"
    echo "  cfg-structure-origin=CANONICAL"
    echo "  branch-condition-origin=CANONICAL"
    echo "  true-edge-origin=CANONICAL"
    echo "  false-edge-origin=CANONICAL"
    echo "  block-identity-origin=CANONICAL"
    echo ""
    echo "  serializer-cfg-construction-authority=NONE"
    echo "  serializer-branch-decision-authority=NONE"
    echo "  serializer-semantic-authority=NONE"
    echo ""
    echo "Action:"
    echo "  AUDIT canonical compiler:"
    echo "  - Does canonical build CFG after MIR?"
    echo "  - Are blocks and edges canonical structures?"
    echo "  - Can serializer see this CFG or only source-level if?"
    echo ""
    
    echo ""
    echo "════════════════════════════════════════"
    echo "PHASE 2: OBSERVATION (RED QUESTIONS)"
    echo "════════════════════════════════════════"
    echo ""
    
    echo "2.1 CANONICAL LAYER"
    echo "───────────────────────────────────────"
    echo ""
    echo "Question: What canonical structures represent CFG?"
    echo "Answer: canonical-cfg-structure=?"
    echo ""
    
    echo "2.2 LOWERED VIEW LAYER"
    echo "───────────────────────────────────────"
    echo ""
    echo "Question: Does lowered view expose CFG?"
    echo "Answer: lowered-view-cfg-representation=?"
    echo ""
    
    echo "2.3 SERIALIZER LAYER"
    echo "───────────────────────────────────────"
    echo ""
    echo "Question: Can serializer encode CFG for SSEED?"
    echo "Expected: Serializer reads canonical_lowered_state and encodes CFG"
    echo "Answer: serializer-cfg-encoding=?"
    echo ""
    
    echo "2.4 SEED-IR-AOT LAYER"
    echo "───────────────────────────────────────"
    echo ""
    echo "Question: Can AOT consumer execute multiple paths based on CFG?"
    echo "Answer: seed-ir-aot-branch-support=?"
    echo ""
    
    echo "════════════════════════════════════════"
    echo "PHASE 3: CLASSIFICATION (ONE MISSING CAP)"
    echo "════════════════════════════════════════"
    echo ""
    
    echo "After PHASE 2 observation, classify:"
    echo ""
    
    echo "Scenario A: canonical-cfg-structure=NO"
    echo "  Classification: CANONICAL_LOWERING_GAP"
    echo "  Action: STOP (don't proceed)"
    echo ""
    
    echo "Scenario B: canonical-cfg-structure=YES, lowered-view-cfg-representation=NO"
    echo "  Classification: EXPORT_VIEW_GAP"
    echo "  Action: Extend lowered-view to expose blocks/edges"
    echo ""
    
    echo "Scenario C: All layers have CFG, but serializer-cfg-encoding=NO"
    echo "  Classification: SERIALIZER_REPRESENTATION_GAP"
    echo "  Action: Add CFG encoding to serializer"
    echo ""
    
    echo "Scenario D: serializer-cfg-encoding=YES, seed-ir-aot-branch-support=NO"
    echo "  Classification: AOT_CONSUMER_GAP"
    echo "  Action: Extend AOT to interpret CFG edges"
    echo ""
    
    echo "════════════════════════════════════════"
    echo "EXECUTION RULE"
    echo "════════════════════════════════════════"
    echo ""
    
    echo "FIX STRATEGY: One capability per cycle"
    echo ""
    echo "  1. Run RED probe"
    echo "  2. Classify first missing capability"
    echo "  3. Fix ONLY that capability"
    echo "     Do NOT aggregate other fixes"
    echo "  4. Rerun RED probe"
    echo "  5. If PASS: verify true-path=42, false-path=43"
    echo "  6. If not PASS: go to step 2"
    echo ""
    
    echo "STOP CONDITIONS:"
    echo "  ✗ canonical-cfg-structure=NO → CANONICAL_LOWERING_GAP"
    echo "  ✗ serializer-semantic-authority=ANY → SEMANTIC_AUTHORITY_LEAK"
    echo "  ✗ lowered-view must re-derive CFG → EXPORT_VIEW_GAP"
    echo ""
    
    echo "════════════════════════════════════════"
    echo "GREEN TARGET (PASS CRITERIA)"
    echo "════════════════════════════════════════"
    echo ""
    
    echo "If all layers OK, verify:"
    echo ""
    echo "canonical-basic-blocks-visible=YES"
    echo "canonical-branch-condition-visible=YES"
    echo "canonical-true-edge-visible=YES"
    echo "canonical-false-edge-visible=YES"
    echo ""
    echo "lowered-view-cfg-representation=YES"
    echo "serializer-cfg-support=YES"
    echo ""
    echo "cfg-structure-origin=CANONICAL"
    echo "serializer-cfg-construction-authority=NONE"
    echo ""
    echo "true-path-known-result=42"
    echo "false-path-known-result=43"
    echo "both-cfg-edges-executed=YES"
    echo ""
    echo "verdict=CANONICAL_BOOTSTRAP_IR_CFG_BRANCH_PROVEN"
    echo ""
    
    echo "════════════════════════════════════════"
    echo "NEXT STEPS"
    echo "════════════════════════════════════════"
    echo ""
    
    echo "After PASS/STOP:"
    echo ""
    echo "If PASS:"
    echo "  B6.5 → PASS/FROZEN"
    echo "  Next: B6.6 (Loop/CFG back-edge)"
    echo ""
    
    echo "If STOP:"
    echo "  Freeze B6.5 with evidence"
    echo "  Do NOT proceed with workarounds"
    echo "  Do NOT mix in loop/aggregate fixes"
    echo ""

} | tee "$OUTPUT_FILE"

echo ""
echo "Output saved to: $OUTPUT_FILE"
echo ""
