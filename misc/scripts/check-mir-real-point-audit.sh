#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

require_text() {
    file=$1
    needle=$2
    label=$3
    if ! grep -Fq "$needle" "$root/$file"; then
        echo "mir real point audit: missing $label" >&2
        echo "  file: $file" >&2
        echo "  text: $needle" >&2
        exit 1
    fi
}

require_text src/cmd/compile/internal/mir.s 'struct mir_basic_block {' 'canonical mir_basic_block'
require_text src/cmd/compile/internal/mir.s 'int id' 'basic block id'
require_text src/cmd/compile/internal/mir.s 'mir_statement[] statements' 'statement array'
require_text src/cmd/compile/internal/mir.s 'terminator mir_terminator' 'block terminator'
require_text src/cmd/compile/internal/mir.s 'struct mir_control_edge {' 'control edge'
require_text src/cmd/compile/internal/mir.s 'int target' 'edge target'
require_text src/cmd/compile/internal/mir.s 'struct mir_graph {' 'mir graph'
require_text src/cmd/compile/internal/mir.s 'int entry' 'graph entry'
require_text src/cmd/compile/internal/mir.s 'int exit' 'graph exit'

require_text src/cmd/compile/internal/ir/lower.s 'func lower_block_to_mir' 'real MIR lowering path'
require_text src/cmd/compile/internal/ir/lower.s 'make_block(0, "entry"' 'entry block construction'
require_text src/cmd/compile/internal/ir/lower.s 'make_edge("then", 1)' 'diamond then edge'
require_text src/cmd/compile/internal/ir/lower.s 'make_edge("else", 2)' 'diamond else edge'
require_text src/cmd/compile/internal/ir/lower.s 'make_edge("true", 2)' 'loop true edge'
require_text src/cmd/compile/internal/ir/lower.s 'make_edge("false", 3)' 'loop false edge'
require_text src/cmd/compile/internal/ir/lower.s 'make_block(2, "while.body"' 'loop body block'
require_text src/cmd/compile/internal/ir/lower.s 'vec1_edge("cond", 1)' 'loop backedge target'

require_text src/cmd/compile/internal/backend_elf64.s 'func execute_mir_graph' 'backend graph consumer'
require_text src/cmd/compile/internal/backend_elf64.s 'current := graph.entry' 'backend entry use'
require_text src/cmd/compile/internal/backend_elf64.s 'for si < len(block.statements)' 'backend statement iteration'
require_text src/cmd/compile/internal/backend_elf64.s 'block.terminator.edges[0].target' 'backend jump target use'

echo "MIR real point audit passed"
