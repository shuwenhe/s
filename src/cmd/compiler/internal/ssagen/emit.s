package compiler.internal.ssagen

use compiler.internal.ir.MIRProgram
use compiler.internal.ir.MIRWriteOp
use std.vec.Vec

struct MachineWriteOp {
    int fd,
    String text,
}

struct MachineExitOp {
    int code,
}

enum MachineOp {
    WriteStdout(MachineWriteOp),
    WriteStderr(MachineWriteOp),
    Exit(MachineExitOp),
}

struct MachineProgram {
    String entry_symbol,
    Vec[MachineOp] ops,
    int exit_code,
}

func LowerProgram(MIRProgram mir, String arch_name) -> MachineProgram {
    var ops = Vec[MachineOp]()
    for write in mir.writes {
        appendWriteOp(ops, write)
    }
    ops.push(Exit(MachineExitOp {
        code: mir.exit_code,
    }))
    MachineProgram {
        entry_symbol: entrySymbol(arch_name),
        ops: ops,
        exit_code: mir.exit_code,
    }
}

func appendWriteOp(Vec[MachineOp] ops, MIRWriteOp write) -> () {
    if write.fd == 2 {
        ops.push(WriteStderr(MachineWriteOp {
            fd: write.fd,
            text: write.text,
        }))
        return
    }
    ops.push(WriteStdout(MachineWriteOp {
        fd: write.fd,
        text: write.text,
    }))
}

func entrySymbol(String arch_name) -> String {
    if arch_name == "amd64" {
        return "_start"
    }
    "_start"
}
