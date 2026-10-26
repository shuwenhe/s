#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-canonical-enum-mir.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package compile.internal
func diamond() mir_program_result {
    parameter := mir_program_parameter { value_id: 0, name: "input", type_name: "int" }
    zero := mir_program_instruction { op: "const_int", result_ids: [1], result_types: ["int"], integer_value: 0 }
    condition := mir_program_instruction { op: "cmp_gt", result_ids: [2], result_types: ["bool"], operands: [0,1] }
    first := mir_program_instruction { op: "const_int", result_ids: [3], result_types: ["int"], integer_value: 40 }
    second := mir_program_instruction { op: "const_int", result_ids: [4], result_types: ["int"], integer_value: 20 }
    phi := mir_program_instruction { op: "phi", result_ids: [5], result_types: ["int"], operands: [3,4] }
    entry := mir_program_block { id: 10, instructions: [zero,condition], terminator: "branch", return_values: [2], successors: [20,30] }
    left := mir_program_block { id: 20, instructions: [first], terminator: "jump", successors: [40] }
    right := mir_program_block { id: 30, instructions: [second], terminator: "jump", successors: [40] }
    merge := mir_program_block { id: 40, instructions: [phi], terminator: "return", return_values: [5] }
    function := mir_program_function { symbol: "main.main", params: [parameter], result_types: ["int"], blocks: [entry,left,right,merge] }
    return lower_mir_program("main", "main.main", [function])
}
func validate() () {
    valid := diamond()
    if valid.error != "" { panic(valid.error) }
    ssa := lower_function_mir_to_ssa(valid.program)
    if ssa.error != "" || len(ssa.program.functions[0].blocks) != 4 { panic("valid multi-block MIR did not reach SSA") }
    bad_use := diamond().program
    bad_use.functions[0].blocks[3].return_values[0] = 3
    if function_mir_input_error(bad_use) == "" { panic("nondominating return accepted") }
    bad_edge := diamond().program
    bad_edge.functions[0].blocks[3].instructions[0].operands[0] = 4
    if function_mir_input_error(bad_edge) == "" { panic("phi from wrong predecessor accepted") }
    bad_phi := diamond().program
    bad_phi.functions[0].blocks[3].instructions[0].operands = [3]
    if function_mir_input_error(bad_phi) == "" { panic("phi incoming count accepted") }
    bad_target := diamond().program
    bad_target.functions[0].blocks[0].successors[0] = 99
    if function_mir_input_error(bad_target) == "" { panic("missing successor accepted") }
    duplicate := diamond().program
    duplicate.functions[0].blocks[2].instructions[0].result_ids[0] = 3
    if function_mir_input_error(duplicate) == "" { panic("duplicate value across blocks accepted") }
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$root/src/cmd/compile/internal/mir/program.s" "$root/src/cmd/compile/internal/mir/program_enum.s" "$root/src/cmd/compile/internal/ssa/program.s" "$root/src/cmd/compile/internal/ssa/function_lower.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'canonical CFG MIR and SSA validate branches, phi edges, value uniqueness and dominance: PASS'
