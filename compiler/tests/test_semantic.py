from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import unittest

from compiler.hosted_compiler import run_cli
from runtime.hosted_command import run_cmd_s
from compiler.prelude import PRELUDE
from compiler.parser import parse_source
from compiler.semantic import check_source


FIXTURES = Path(__file__).resolve().parent / "fixtures"


class SemanticTests(unittest.TestCase):
    def test_check_source_success(self) -> None:
        source = (FIXTURES / "check_ok.s").read_text()
        result = check_source(parse_source(source))
        self.assertTrue(result.ok, [d.message for d in result.diagnostics])

    def test_check_source_failure(self) -> None:
        source = (FIXTURES / "check_fail.s").read_text()
        result = check_source(parse_source(source))
        self.assertFalse(result.ok)
        self.assertIn("let value expected bool, got i32", [d.message for d in result.diagnostics])

    def test_cli_check_success(self) -> None:
        proc = subprocess.run(
            [sys.executable, "-m", "compiler", "check", str(FIXTURES / "check_ok.s")],
            cwd="/app/s",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("ok:", proc.stdout)

    def test_cli_check_failure(self) -> None:
        proc = subprocess.run(
            [sys.executable, "-m", "compiler", "check", str(FIXTURES / "check_fail.s")],
            cwd="/app/s",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 1)
        self.assertIn("error: let value expected bool, got i32", proc.stderr)

    def test_borrow_checker_failure(self) -> None:
        source = (FIXTURES / "borrow_fail.s").read_text()
        result = check_source(parse_source(source))
        self.assertFalse(result.ok)
        messages = [d.message for d in result.diagnostics]
        self.assertIn("cannot mutably borrow value while borrowed", messages)
        self.assertIn("use of moved value text", messages)

    def test_generic_bound_failure(self) -> None:
        source = (FIXTURES / "generic_bound_fail.s").read_text()
        result = check_source(parse_source(source))
        self.assertFalse(result.ok)
        messages = [d.message for d in result.diagnostics]
        self.assertIn("type String does not satisfy bound Copy", messages)

    def test_branch_dataflow_failure(self) -> None:
        source = (FIXTURES / "branch_move_fail.s").read_text()
        result = check_source(parse_source(source))
        self.assertFalse(result.ok)
        messages = [d.message for d in result.diagnostics]
        self.assertIn("use of moved value text", messages)

    def test_member_and_trait_method_success(self) -> None:
        source = (FIXTURES / "member_method_sample.s").read_text()
        result = check_source(parse_source(source))
        self.assertTrue(result.ok, [d.message for d in result.diagnostics])

    def test_prelude_method_success(self) -> None:
        source = (FIXTURES / "prelude_methods_ok.s").read_text()
        result = check_source(parse_source(source))
        self.assertTrue(result.ok, [d.message for d in result.diagnostics])

    def test_method_candidate_conflict(self) -> None:
        source = (FIXTURES / "method_conflict_fail.s").read_text()
        result = check_source(parse_source(source))
        self.assertFalse(result.ok)
        messages = [d.message for d in result.diagnostics]
        self.assertTrue(any("multiple method candidates" in message for message in messages), messages)

    def test_receiver_auto_borrow_success(self) -> None:
        source = (FIXTURES / "receiver_auto_borrow_ok.s").read_text()
        result = check_source(parse_source(source))
        self.assertTrue(result.ok, [d.message for d in result.diagnostics])

    def test_prelude_loaded_from_decl(self) -> None:
        self.assertEqual(PRELUDE.name, "std.prelude")
        self.assertIn("Vec", PRELUDE.types)
        self.assertIn("push", PRELUDE.types["Vec"].methods)
        self.assertIn("Len", PRELUDE.traits)
        self.assertEqual(PRELUDE.types["Vec"].methods["push"][0].receiver_policy, "addressable")

    def test_builtin_field_success(self) -> None:
        source = (FIXTURES / "builtin_field_ok.s").read_text()
        result = check_source(parse_source(source))
        self.assertTrue(result.ok, [d.message for d in result.diagnostics])

    def test_cli_build_sum_success(self) -> None:
        proc = subprocess.run(
            [sys.executable, "-m", "compiler", "build", "/app/s/examples/s/sum.s", "-o", "/tmp/s_sum_test"],
            cwd="/app/s",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("built:", proc.stdout)

    def test_cli_build_sum_binary_output(self) -> None:
        build = subprocess.run(
            [sys.executable, "-m", "compiler", "build", "/app/s/examples/s/sum.s", "-o", "/tmp/s_sum_test"],
            cwd="/app/s",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(build.returncode, 0, build.stderr)

        run = subprocess.run(
            ["/tmp/s_sum_test"],
            cwd="/app/s",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout.strip(), "5050")

    def test_hosted_build_sum_binary_output(self) -> None:
        code = run_cli(["build", "/app/s/examples/s/sum.s", "-o", "/tmp/s_sum_hosted"])
        self.assertEqual(code, 0)

        run = subprocess.run(
            ["/tmp/s_sum_hosted"],
            cwd="/app/s",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout.strip(), "5050")

    def test_cmd_s_hosted_build_sum_binary_output(self) -> None:
        result = run_cmd_s(["build", "/app/s/examples/s/sum.s", "-o", "/tmp/s_sum_cmd_s"])
        self.assertEqual(result.exit_code, 0)

        run = subprocess.run(
            ["/tmp/s_sum_cmd_s"],
            cwd="/app/s",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout.strip(), "5050")

    def test_native_runner_build_sum_binary_output(self) -> None:
        build_runner = subprocess.run(
            ["/app/s/scripts/build_native_runner.sh", "/tmp/s_native_test"],
            cwd="/app",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(build_runner.returncode, 0, build_runner.stderr)

        build = subprocess.run(
            ["/tmp/s_native_test", "build", "/app/s/examples/s/sum.s", "-o", "/tmp/s_sum_native_test"],
            cwd="/app",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(build.returncode, 0, build.stderr)

        run = subprocess.run(
            ["/tmp/s_sum_native_test"],
            cwd="/app/s",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout.strip(), "5050")
