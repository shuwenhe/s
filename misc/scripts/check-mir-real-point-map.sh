#!/usr/bin/env bash
set -euo pipefail

mir_file="src/cmd/compile/internal/mir.s"
test_file="src/cmd/compile/internal/tests/test_mir.s"

grep -q "struct mir_point" "$mir_file"
grep -q "int block_id" "$mir_file"
grep -q "int statement_index" "$mir_file"
grep -q "struct mir_point_map" "$mir_file"
grep -q "mir_point\\[\\] points" "$mir_file"
grep -q "func build_mir_point_map" "$mir_file"
grep -q "func mir_point_id" "$mir_file"
grep -q "func mir_point_count" "$mir_file"
grep -q "func mir_point_text" "$mir_file"
grep -q "statement_index len(graph.blocks\\[block_index\\].statements)" "$mir_file"
grep -q "block_id ascending" "$mir_file"

awk '
    /func build_mir_point_map/ { in_builder = 1 }
    /func mir_point_id/ { in_builder = 0 }
    in_builder && /(borrow|loan|region|outlives|live|liveness|fixed)/ {
        print "point map builder leaked ownership semantics: " $0
        exit 1
    }
' "$mir_file"

grep -q "BB0(entry):stmt0" "$test_file"
grep -q "BB0(entry):stmt1" "$test_file"
grep -q "BB0(entry):term" "$test_file"
grep -q "BB1(then):stmt0" "$test_file"
grep -q "BB1(then):term" "$test_file"
grep -q "BB2(else):stmt0" "$test_file"
grep -q "BB2(else):term" "$test_file"
grep -q "BB3(merge):term" "$test_file"
grep -q "mir_point_count(diamond) != 8" "$test_file"
grep -q "len(point_map.points) != mir_point_count(diamond)" "$test_file"
grep -q "mir_point_id(point_map, 0, 2) != 2" "$test_file"
grep -q "mir_point_id(point_map, 1, 1) != 4" "$test_file"
grep -q "mir_point_id(point_map, 3, 0) != 7" "$test_file"

echo "mir-real-point-map-check: ok"
