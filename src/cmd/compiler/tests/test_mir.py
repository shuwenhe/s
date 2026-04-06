from __future__ import annotations

import unittest

from compiler.mir import DropStmt, MIRProgram, MIRWriteOp, MoveStmt, lower_block, lower_source
from compiler.internal.amd64.isel import select_instructions
from compiler.internal.ssagen.lowering import LoweredData, LoweredInstruction, LoweredProgram, lower_program
from compiler.ownership import make_plan
from compiler.parser import parse_source
from compiler.prelude import PRELUDE
from compiler.typesys import parse_type


class MIRTests(unittest.TestCase):
    def test_if_lowering_emits_block_param_join(self) -> None:
        source = """
package demo.mir

pub func choose(flag: bool) -> i32 {
    if flag {
        1
    } else {
        2
    }
}
"""
        parsed = parse_source(source)
        func = parsed.items[0]
        graph = lower_block(func.body, [param.name for param in func.sig.params])
        join_blocks = [block for block in graph.blocks.values() if block.params]
        self.assertTrue(join_blocks)
        arg_edges = [edge for block in graph.blocks.values() for edge in block.terminator.edges if edge.args]
        self.assertTrue(
            any(edge.args for edge in arg_edges),
            arg_edges,
        )
        self.assertTrue(all(edge.id for edge in arg_edges))

    def test_locals_are_versioned(self) -> None:
        source = """
package demo.mir

pub func shadow(x: i32) -> i32 {
    let x = 1
    x
}
"""
        parsed = parse_source(source)
        func = parsed.items[0]
        graph = lower_block(func.body, [param.name for param in func.sig.params])
        versions = [slot.version for slot in graph.locals.values() if slot.name == "x"]
        self.assertGreaterEqual(len(versions), 2)
        self.assertIn(0, versions)
        self.assertIn(1, versions)

    def test_ownership_plan_drives_move_and_drop(self) -> None:
        source = """
package demo.mir

pub func take(text: String) -> String {
    let other = text
    other
}
"""
        parsed = parse_source(source)
        func = parsed.items[0]
        graph = lower_block(
            func.body,
            [param.name for param in func.sig.params],
            {"text": parse_type("String"), "other": parse_type("String")},
            make_plan({"text": parse_type("String"), "other": parse_type("String")}),
        )
        moves = [stmt for block in graph.blocks.values() for stmt in block.statements if isinstance(stmt, MoveStmt)]
        drops = [stmt for block in graph.blocks.values() for stmt in block.statements if isinstance(stmt, DropStmt)]
        self.assertTrue(moves)
        self.assertTrue(drops)

    def test_prelude_decl_has_traits_and_index(self) -> None:
        self.assertEqual(PRELUDE.name, "std.prelude")
        self.assertIn("Len", PRELUDE.traits)
        self.assertIn("Clone", PRELUDE.types["String"].traits)
        self.assertEqual(PRELUDE.types["Vec"].index_result_kind, "first_type_arg")
        self.assertIn("Len", PRELUDE.types["String"].default_impls)
        self.assertEqual(PRELUDE.types["FileInfo"].fields["size"].visibility, "pub")
        self.assertFalse(PRELUDE.types["FileInfo"].fields["size"].writable)
        self.assertFalse(PRELUDE.types["FileInfo"].fields["hidden"].readable)
        self.assertEqual(len(PRELUDE.types["Vec"].methods["push"]), 1)
        self.assertEqual(PRELUDE.types["Vec"].methods["push"][0].receiver_policy, "addressable")

    def test_lowering_emits_richer_builtin_ops(self) -> None:
        lowered = lower_program(
            MIRProgram(writes=[MIRWriteOp(fd=1, text="42\n")], exit_code=0),
            "amd64",
        )
        ops = [inst.op for inst in lowered.instructions]
        self.assertIn("load_const", ops)
        self.assertIn("copy_reg", ops)
        self.assertIn("call_builtin", ops)

    def test_amd64_selector_dispatches_compute_style_ops(self) -> None:
        lowered = LoweredProgram(
            entry_symbol="_start",
            data=[LoweredData(label="msg", text="x")],
            instructions=[
                LoweredInstruction(op="load_const", value_type="i64", target_reg="r8", value="7"),
                LoweredInstruction(op="copy_reg", value_type="i64", target_reg="rax", source_reg="r8"),
                LoweredInstruction(op="add_i32", value_type="i32", target_reg="eax", source_reg="ecx"),
                LoweredInstruction(op="cmp_le_i32", value_type="i32", target_reg="eax", source_reg="ecx"),
                LoweredInstruction(op="branch_if", value_type="flags", target_reg="", target_label="L_true", false_label="L_false"),
                LoweredInstruction(op="label", value_type="label", target_reg="", target_label="L_true"),
                LoweredInstruction(op="call_builtin", value_type="unit", target_reg="", builtin="syscall_exit"),
            ],
            exit_code=0,
        )
        asm = select_instructions(lowered)
        text = [(insn.opcode, insn.operands) for insn in asm.text]
        self.assertIn(("mov", ("$7", "%r8")), text)
        self.assertIn(("mov", ("%r8", "%rax")), text)
        self.assertIn(("add", ("%ecx", "%eax")), text)
        self.assertIn(("cmp", ("%ecx", "%eax")), text)
        self.assertIn(("jle", ("L_true",)), text)
        self.assertIn(("jmp", ("L_false",)), text)
        self.assertIn(("L_true:", ()), text)
        self.assertIn(("syscall", ()), text)

    def test_lower_source_emits_real_compute_ops_for_sum(self) -> None:
        parsed = parse_source(
            """
package main

func main() {
    int sum = 0
    for (int i = 1; i <= 100; i++) {
        sum = sum + i
    }
    println(sum)
}
"""
        )
        mir = lower_source(parsed)
        ops = [op.op for op in mir.ops]
        self.assertIn("load_const", ops)
        self.assertIn("add_i32", ops)
        self.assertIn("cmp_le_i32", ops)
        self.assertIn("branch_if", ops)
        self.assertIn("call_builtin", ops)
