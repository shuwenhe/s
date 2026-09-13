#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-mir-nll-real-cfg.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

export S_MODULAR_COMPILER=/nonexistent/s_modular

check_line() {
    file=$1
    needle=$2
    label=$3
    if ! grep -Fq "$needle" "$file"; then
        echo "mir nll real cfg: missing $label: $needle" >&2
        cat "$file" >&2
        exit 1
    fi
}

check_real_cfg() {
    name=$1
    source=$2
    src="$work/$name.s"
    out="$work/$name.real-cfg"
    printf '%s\n' "$source" >"$src"
    "$root/bin/s" --emit-mir-nll-real-cfg "$src" "$out"
    check_line "$out" 'Point(P0) = BB0:stmt0' "$name P0 binding"
    check_line "$out" 'LoanLivePoints(L0) = {P0, P1}' "$name loan live points"
    check_line "$out" 'MovePoint(P2, Field(_1, 0))' "$name move point"
    check_line "$out" 'RefLiveness(iterations=' "$name reference liveness"
    check_line "$out" 'RegionSolver(iterations=' "$name region solver"
    check_line "$out" 'converged=true' "$name convergence"
}

check_real_cfg "straight_line" 'package realcfg
func main() int {
    borrow_shared_field p _1 0
    use_ref p
    move_field _1 0
    return 0
}'
check_line "$work/straight_line.real-cfg" 'RealCFG(blocks=1, entry=BB0, exit=BB0)' 'straight-line cfg'
check_line "$work/straight_line.real-cfg" 'Point(P1) = BB0:stmt1' 'straight-line P1 binding'
check_line "$work/straight_line.real-cfg" 'Point(P2) = BB0:stmt2' 'straight-line P2 binding'

check_real_cfg "diamond" 'package realcfg
func main() int {
    borrow_shared_field p _1 0
    if cond {
        use_ref p
    } else {
    }
    move_field _1 0
    return 0
}'
check_line "$work/diamond.real-cfg" 'RealCFG(blocks=4, entry=BB0, exit=BB3)' 'diamond cfg'
check_line "$work/diamond.real-cfg" 'CFGEdge(BB0, BB1)' 'diamond true edge'
check_line "$work/diamond.real-cfg" 'CFGEdge(BB0, BB2)' 'diamond false edge'
check_line "$work/diamond.real-cfg" 'CFGEdge(BB1, BB3)' 'diamond then join'
check_line "$work/diamond.real-cfg" 'CFGEdge(BB2, BB3)' 'diamond else join'
check_line "$work/diamond.real-cfg" 'Point(P1) = BB1:stmt0' 'diamond branch point'
check_line "$work/diamond.real-cfg" 'Point(P2) = BB3:stmt0' 'diamond join move point'

cat >"$work/diamond_real_mir.s" <<'SRC'
package realcfg
func main() int {
    x := box(1)
    if cond {
        y := x
    } else {
        z := *x
    }
    return 0
}
SRC
"$root/bin/s" --emit-mir "$work/diamond_real_mir.s" "$work/diamond_real_mir.mir"
check_line "$work/diamond_real_mir.mir" 'mir main blocks=4 entry=0 exit=3' 'real MIR diamond block count'
check_line "$work/diamond_real_mir.mir" 'Branch(cond, bb1, bb2)' 'real MIR diamond branch'
check_line "$work/diamond_real_mir.mir" 'Goto(bb3)' 'real MIR diamond join'

check_real_cfg "loop_backedge" 'package realcfg
func main() int {
    borrow_shared_field p _1 0
    while cond {
        use_ref p
    }
    move_field _1 0
    return 0
}'
check_line "$work/loop_backedge.real-cfg" 'CFGEdge(BB2, BB1, backedge=true)' 'loop backedge'
check_line "$work/loop_backedge.real-cfg" 'NLLRealCFGCheck(points=3, edges=4, backedges=1, converged=true)' 'loop summary'

check_real_cfg "early_return" 'package realcfg
func main() int {
    borrow_shared_field p _1 0
    early_return_marker
    if cond {
        use_ref p
        return 0
    } else {
    }
    move_field _1 0
    return 0
}'
check_line "$work/early_return.real-cfg" 'CFGEdge(BB2, BB3)' 'early-return surviving join edge'
check_line "$work/early_return.real-cfg" 'NLLRealCFGCheck(points=3, edges=3, backedges=0, early_return=true, converged=true)' 'early-return summary'

echo "MIR NLL real CFG check passed"
