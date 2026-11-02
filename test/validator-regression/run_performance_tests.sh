#!/bin/bash
# Performance scaling tests for Strict Validator
# Tests 16, 64, 256, 1024 arithmetic blocks to measure validator scaling

set -e

SHUWEN_S_ROOT="$(cd "$(dirname "$(dirname "$(dirname "$0")")")" && pwd)"
TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$TEST_DIR/perf-results-$(date +%s)"
mkdir -p "$RESULTS_DIR"

# Test configurations
BLOCK_SIZES=(16 64 256 1024)

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "====== S Compiler Strict Validator Performance Tests ======"
echo "Test Date: $(date)"
echo "Results Directory: $RESULTS_DIR"
echo ""

# Create a CSV header for results
cat > "$RESULTS_DIR/performance_summary.csv" << 'EOF'
block_size,compile_time_ms,peak_rss_kb,assembly_sha256,status
EOF

for block_size in "${BLOCK_SIZES[@]}"; do
    echo "Testing $block_size arithmetic blocks..."
    
    # Generate test program
    test_file="$RESULTS_DIR/arith_$block_size.s"
    python3 "$TEST_DIR/generate_arithmetic_test.py" "$block_size" "$test_file"
    
    # Run compilation with timing and resource monitoring
    compile_log="$RESULTS_DIR/arith_${block_size}.log"
    memory_log="$RESULTS_DIR/arith_${block_size}.rss.tsv"
    assembly_file="$RESULTS_DIR/arith_${block_size}.sasm"
    
    echo "  Compiling..."
    
    # Time the compilation
    start_time=$(date +%s%N)
    peak_rss=0
    
    cd "$SHUWEN_S_ROOT"
    
    # Run with /usr/bin/time to get resource info
    if command -v /usr/bin/time &> /dev/null; then
        /usr/bin/time -v ./bin/s-compiler "$test_file" > "$assembly_file" 2> "$compile_log" || {
            echo "  ${RED}FAIL: Compilation failed${NC}"
            echo "$block_size,0,0,failed,error" >> "$RESULTS_DIR/performance_summary.csv"
            continue
        }
    else
        ./bin/s-compiler "$test_file" > "$assembly_file" 2> "$compile_log" || {
            echo "  ${RED}FAIL: Compilation failed${NC}"
            echo "$block_size,0,0,failed,error" >> "$RESULTS_DIR/performance_summary.csv"
            continue
        }
    fi
    
    end_time=$(date +%s%N)
    elapsed_ms=$(( (end_time - start_time) / 1000000 ))
    
    # Calculate assembly SHA256 for byte-for-byte comparison
    asm_sha256=$(sha256sum "$assembly_file" | awk '{print $1}')
    
    echo "  Assembly SHA256: $asm_sha256"
    echo "  Compile time: ${elapsed_ms}ms"
    
    # Append to CSV
    echo "$block_size,$elapsed_ms,0,$asm_sha256,ok" >> "$RESULTS_DIR/performance_summary.csv"
    
    echo "  ${GREEN}OK${NC}"
done

echo ""
echo "====== Performance Results ======"
cat "$RESULTS_DIR/performance_summary.csv"

echo ""
echo "Full results saved to: $RESULTS_DIR"
