#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-mir-cfg.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

export S_MODULAR_COMPILER=/nonexistent/s_modular

cat >"$work/if_else_cfg.s" <<'SRC'
package mircfg

func main() int {
    x := box(42)
    if cond {
        y := x
    } else {
        z := *x
    }
    return 0
}
SRC

"$root/bin/s" --emit-mir "$work/if_else_cfg.s" "$work/if_else_cfg.mir"

if ! grep -q 'mir main blocks=4 entry=0 exit=3' "$work/if_else_cfg.mir"; then
    echo "mir cfg: expected CFG metadata blocks=4 entry=0 exit=3" >&2
    cat "$work/if_else_cfg.mir" >&2
    exit 1
fi

for block in 'bb0:' 'bb1:' 'bb2:' 'bb3:'; do
    if ! grep -q "$block" "$work/if_else_cfg.mir"; then
        echo "mir cfg: expected block $block" >&2
        cat "$work/if_else_cfg.mir" >&2
        exit 1
    fi
done

if ! grep -q 'Branch(cond, bb1, bb2)' "$work/if_else_cfg.mir"; then
    echo "mir cfg: expected Branch terminator" >&2
    cat "$work/if_else_cfg.mir" >&2
    exit 1
fi

goto_count=$(grep -c 'Goto(bb3)' "$work/if_else_cfg.mir" || true)
if [ "$goto_count" -ne 2 ]; then
    echo "mir cfg: expected two Goto(bb3) terminators" >&2
    cat "$work/if_else_cfg.mir" >&2
    exit 1
fi

if ! grep -q 'Return(0)' "$work/if_else_cfg.mir"; then
    echo "mir cfg: expected Return terminator in merge block" >&2
    cat "$work/if_else_cfg.mir" >&2
    exit 1
fi

echo "MIR CFG check passed"
