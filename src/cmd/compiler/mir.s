package compiler

use compiler.internal.ir.AssignStmt
use compiler.internal.ir.BasicBlock
use compiler.internal.ir.ControlEdge
use compiler.internal.ir.CopyStmt
use compiler.internal.ir.DropStmt
use compiler.internal.ir.EvalStmt
use compiler.internal.ir.LocalSlot
use compiler.internal.ir.LowerBlock
use compiler.internal.ir.MIRGraph
use compiler.internal.ir.MoveStmt
use compiler.internal.ir.Operand
use compiler.internal.ir.Terminator
