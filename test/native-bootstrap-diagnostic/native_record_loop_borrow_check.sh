#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work="$root/.bootstrap/native-record-loop-borrow"
mkdir -p "$work"
cat > "$work/loop.s" <<'S'
package main
struct state { int total; int[] values }
func fill(target* state, int count) {
    for i := 0; i < count; i = i + 1 {
        if i == 2 { continue }
        target.total = target.total + i
    }
    local := make(int[], count)
    for i := 0; i < count; i = i + 1 { local[i] = i + 10 }
    target.values = local
}
func main() int {
    value := state {}
    fill(value, 5)
    return value.total + value.values[4] + 20
}
S
"$root/bin/s_seed" --compile-native-unit "$work/loop.ir" "$work/loop.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/loop.ir" "$work/loop"
status=0; "$work/loop" || status=$?
test "$status" -eq 42
echo 'loop borrow scalar/array mutation: PASS'

cat > "$work/ir-types.s" <<'S'
package compile.internal.ir
struct ir_instruction { int marker }
struct ir_block {
    int block_id
    string label
    ir_instruction[] instructions
    int[] predecessors
    int[] successors
}
struct ir_function { ir_block[] basic_blocks }
func main() int {
    first := cfg_block { block_id: 0, successors: [1] }
    second := cfg_block { block_id: 1, predecessors: [0] }
    graph := control_flow_graph { blocks: [first, second], exit_block_id: 1 }
    cfg_compute_dominators(graph)
    cfg_compute_post_dominators(graph)
    cfg_compute_dominance_frontier(graph)
    return graph.dominators[1][0] + graph.dominators[1][1] + graph.post_dominators[0][0] + graph.post_dominators[0][1] + 38
}
S
"$root/bin/s_seed" --compile-native-unit "$work/cfg.ir" "$root/src/cmd/compile/internal/ir/middlend_cfg.s" "$work/ir-types.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/cfg.ir" "$work/cfg"
status=0; timeout 15 "$work/cfg" || status=$?
echo "real CFG native status: $status"
test "$status" -eq 42
echo 'real CFG dominators/postdominators/frontier: PASS (isolated IR dependencies)'
# Every predecessor participates in the type meet; descriptors on ordinary
# value callees also require body validation.
cat > "$work/flow.s" <<'S'
package main
struct state { int total; int[] values }
func merge(target* state, int flag) {
    local := 0
    if flag { local = 42 }
    target.total = local
}
func fresh() int[] { return int[]() }
func from_value(target* state) { target.total = len(fresh()) }
func main() int {
    value := state {}
    merge(value, 1)
    from_value(value)
    return value.total + 42
}
S
"$root/bin/s_seed" --compile-native-unit "$work/flow.ir" "$work/flow.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/flow.ir" "$work/flow"
status=0; "$work/flow" || status=$?
test "$status" -eq 42
printf 'preserve output\n' > "$work/output"
cp "$work/output" "$work/saved"
python3 - "$work" <<'PY'
import pathlib,sys
w=pathlib.Path(sys.argv[1]); original=(w/'flow.ir').read_text()
start=original.index('FUNC_BEGIN|merge|'); end=original.index('FUNC_END|merge|',start)
body=original[start:end]
(w/'merge-uninit.ir').write_text(original[:start]+body.replace('MOV|local|0|_\n','')+original[end:])
(w/'merge-types.ir').write_text(original[:start]+body.replace('MOV|local|42|_','MOV|local|"bad"|_')+original[end:])
start=original.index('FUNC_BEGIN|fresh|'); end=original.index('FUNC_END|fresh|',start)
body=original[start:end]; lines=body.splitlines()
fallthrough='\n'.join(line for line in lines if not line.startswith('RET|'))+'\n'
(w/'callee-fallthrough.ir').write_text(original[:start]+fallthrough+original[end:])
(w/'conditional-fallthrough.ir').write_text(original[:start]+fallthrough+'LABEL|final_condition|_|_\nJUMP_IF_FALSE|final_condition|1|_\n'+original[end:])
for i,line in enumerate(lines):
    if line.startswith('RET|') and line!='RET|0|_|_': lines[i]='RET|7|_|_'; break
(w/'callee-return.ir').write_text(original[:start]+'\n'.join(lines)+'\n'+original[end:])
original=(w/'loop.ir').read_text()
start=original.index('FUNC_BEGIN|fill|'); end=original.index('FUNC_END|fill|',start)
body=original[start:end]
(w/'loop-type.ir').write_text(original[:start]+body.replace('MOV|i|0|_', 'MOV|i|"bad"|_',1)+original[end:])
(w/'loop-escape.ir').write_text(original[:start]+body+'RET|target|_|_\n'+original[end:])
PY
cat > "$work/forbidden-tool" <<'S'
#!/bin/sh
printf called >> "$S_TEST_TOOL_LOG"
exit 99
S
chmod +x "$work/forbidden-tool"
rm -f "$work/tools.log"
for name in callee-fallthrough conditional-fallthrough merge-uninit merge-types callee-return loop-type loop-escape; do
    if S_SOURCE_ROOT="$root" S_TEST_TOOL_LOG="$work/tools.log" \
        S_BOOTSTRAP_AS="$work/forbidden-tool" S_BOOTSTRAP_LD="$work/forbidden-tool" \
        "$root/bin/s_seed" --emit-standalone-amd64 "$work/$name.ir" "$work/output" > "$work/$name.log" 2>&1; then
        echo "invalid borrow dataflow accepted: $name" >&2; exit 1
    fi
    grep -q 'unproven' "$work/$name.log"
    cmp "$work/output" "$work/saved"
    test ! -e "$work/tools.log"
done
echo 'branch meet, loop types, value-callee return and unreachable escape rejection: PASS'
