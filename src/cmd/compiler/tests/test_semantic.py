from __future__ import annotations

from pathlib import Path
from contextlib import redirect_stderr, redirect_stdout
import io
import subprocess
import sys
import tempfile
import unittest

from compiler.internal.gc.compile import PrepareCompileQueue
from compiler.hosted_compiler import run_cli
from runtime.hosted_command import run_cmd_s
from compiler.prelude import PRELUDE
from compiler.parser import parse_source
from compiler.interpreter import Interpreter
from compiler.semantic import check_source


FIXTURES = Path(__file__).resolve().parent / "fixtures"


class SemanticTests(unittest.TestCase):
    def test_prepare_compile_queue_tracks_top_level_and_impl_methods(self) -> None:
        parsed = parse_source(
            """
package demo.queue

struct Counter {
    i32 value,
}

impl Counter {
    func bump(Counter self) -> i32 {
        self.value
    }
}

func helper() -> i32 {
    1
}

func main() -> i32 {
    helper()
}
"""
        )
        queue = PrepareCompileQueue(parsed)
        self.assertEqual([unit.name for unit in queue.units], ["bump", "helper", "main"])
        self.assertEqual(queue.entry_name, "main")
        self.assertTrue(all(unit.prepared for unit in queue.units))
        self.assertTrue(all(not unit.compiled for unit in queue.units))

    def test_prepare_compile_queue_skips_blank_and_bodyless_functions(self) -> None:
        parsed = parse_source(
            """
package demo.queue_skip

trait Writer {
    func write(String text) -> i32;
}

func _() -> i32 {
    0
}

func main() -> i32 {
    0
}
"""
        )
        queue = PrepareCompileQueue(parsed)
        self.assertEqual([unit.name for unit in queue.units], ["main"])

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
            cwd="/app/s/src",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("ok:", proc.stdout)

    def test_cli_check_failure(self) -> None:
        proc = subprocess.run(
            [sys.executable, "-m", "compiler", "check", str(FIXTURES / "check_fail.s")],
            cwd="/app/s/src",
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

    def test_std_result_option_variant_payloads(self) -> None:
        source = """
package demo.variant_payload

use std.option.Option
use std.result.Result

func unwrap_or_zero(Result[i32, String] value) -> i32 {
    match value {
        Ok(number) => number,
        Err(_) => 0,
    }
}

func unwrap_or_default(Option[String] value) -> String {
    match value {
        Some(text) => text,
        None => "fallback",
    }
}
"""
        result = check_source(parse_source(source))
        self.assertTrue(result.ok, [d.message for d in result.diagnostics])

    def test_std_use_imported_functions_and_fields(self) -> None:
        source = """
package demo.std

use std.env.Args
use std.fs.ReadToString
use std.process.RunProcess
use std.result.Result
use std.vec.Vec

func main() -> i32 {
    var args = Args()
    var text =
        match ReadToString("demo.txt") {
            Ok(value) => value,
            Err(err) => err.message,
        }
    var proc = RunProcess(args)
    match proc {
        Ok(_) => 0,
        Err(err) => err.message.len(),
    }
}
"""
        result = check_source(parse_source(source))
        self.assertTrue(result.ok, [d.message for d in result.diagnostics])

    def test_never_branch_from_early_return(self) -> None:
        source = """
package demo.never_branch

use std.result.Result

func pick(Result[i32, String] value) -> Result[i32, String] {
    var number =
        match value {
            Ok(v) => v,
            Err(err) => {
                return Err(err)
            },
        }
    Ok(number)
}
"""
        result = check_source(parse_source(source))
        self.assertTrue(result.ok, [d.message for d in result.diagnostics])

    def test_cli_build_sum_success(self) -> None:
        proc = subprocess.run(
            [sys.executable, "-m", "compiler", "build", "/app/s/misc/examples/s/sum.s", "-o", "/tmp/s_sum_test"],
            cwd="/app/s/src",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("built:", proc.stdout)

    def test_cli_build_sum_binary_output(self) -> None:
        build = subprocess.run(
            [sys.executable, "-m", "compiler", "build", "/app/s/misc/examples/s/sum.s", "-o", "/tmp/s_sum_test"],
            cwd="/app/s/src",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(build.returncode, 0, build.stderr)

        run = subprocess.run(
            ["/tmp/s_sum_test"],
            cwd="/app/s/src",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout.strip(), "5050")

    def test_hosted_build_sum_binary_output(self) -> None:
        code = run_cli(["build", "/app/s/misc/examples/s/sum.s", "-o", "/tmp/s_sum_hosted"])
        self.assertEqual(code, 0)

        run = subprocess.run(
            ["/tmp/s_sum_hosted"],
            cwd="/app/s/src",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout.strip(), "5050")

    def test_hosted_build_relative_output_goes_to_app_tmp(self) -> None:
        output_path = Path("/app/tmp/s_sum_relative_test")
        if output_path.exists():
            output_path.unlink()

        code = run_cli(["build", "/app/s/misc/examples/s/sum.s", "-o", "s_sum_relative_test"])
        self.assertEqual(code, 0)
        self.assertTrue(output_path.exists())

        run = subprocess.run(
            [str(output_path)],
            cwd="/app/s/src",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout.strip(), "5050")

    def test_hosted_run_sum_output(self) -> None:
        stdout = io.StringIO()
        stderr = io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            code = run_cli(["run", "/app/s/misc/examples/s/sum.s"])
        self.assertEqual(code, 0, stderr.getvalue())
        self.assertEqual(stdout.getvalue().strip(), "5050")

    def test_cmd_s_hosted_run_sum_output(self) -> None:
        stdout = io.StringIO()
        stderr = io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            result = run_cmd_s(["run", "/app/s/misc/examples/s/sum.s"])
        self.assertEqual(result.exit_code, 0, stderr.getvalue())
        self.assertEqual(stdout.getvalue().strip(), "5050")

    def test_hosted_build_vec_push_and_string_concat(self) -> None:
        source = """
package demo.vec_concat

use std.io.println
use std.vec.Vec

func main() -> int {
    var parts = Vec[String]()
    parts.push("4");
    parts.push("2");
    println(parts[0] + parts[1]);
    0
}
"""
        with tempfile.TemporaryDirectory(prefix="s-semantic-") as tmp:
            source_path = Path(tmp) / "vec_concat.s"
            output_path = Path(tmp) / "vec_concat_bin"
            source_path.write_text(source)

            code = run_cli(["build", str(source_path), "-o", str(output_path)])
            self.assertEqual(code, 0)

            run = subprocess.run(
                [str(output_path)],
                cwd="/app/s/src",
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertEqual(run.stdout.strip(), "42")

    def test_hosted_build_match_while_vec_index(self) -> None:
        source = """
package demo.match_while_vec

use std.io.println
use std.option.Option
use std.vec.Vec

func pick(Option[String] value) -> String {
    return match value {
        Some(text) => text,
        None => "2",
    }
}

func tail() -> Option[String] {
    return Some("2")
}

func main() -> int {
    var parts = Vec[String]()
    var index = 0
    while index <= 0 {
        parts.push("4");
        index++;
    }
    var extra = pick(tail())
    parts.push(extra);
    println(parts[0] + parts[1]);
    0
}
"""
        with tempfile.TemporaryDirectory(prefix="s-semantic-") as tmp:
            source_path = Path(tmp) / "match_while_vec.s"
            output_path = Path(tmp) / "match_while_vec_bin"
            source_path.write_text(source)

            code = run_cli(["build", str(source_path), "-o", str(output_path)])
            self.assertEqual(code, 0)

            run = subprocess.run(
                [str(output_path)],
                cwd="/app/s/src",
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertEqual(run.stdout.strip(), "42")

    def test_hosted_build_s_native_runner_binary_output(self) -> None:
        code = run_cli(["build", "/app/s/src/runtime/runner.s", "-o", "/tmp/s_native_hosted"])
        self.assertEqual(code, 0)
        binary = Path("/tmp/s_native_hosted").read_bytes()
        self.assertTrue(binary.startswith(b"\x7fELF"))

        rebuild = subprocess.run(
            ["/tmp/s_native_hosted", "build", "/app/s/src/runtime/runner.s", "-o", "/tmp/s_native_self_hosted"],
            cwd="/app/s/src",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(rebuild.returncode, 0, rebuild.stderr)
        self.assertTrue(Path("/tmp/s_native_self_hosted").read_bytes().startswith(b"\x7fELF"))

        build = subprocess.run(
            ["/tmp/s_native_self_hosted", "build", "/app/s/misc/examples/s/sum.s", "-o", "/tmp/s_sum_via_native_hosted"],
            cwd="/app/s/src",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(build.returncode, 0, build.stderr)

        run = subprocess.run(
            ["/tmp/s_sum_via_native_hosted"],
            cwd="/app/s/src",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout.strip(), "5050")

    def test_cmd_s_hosted_build_sum_binary_output(self) -> None:
        result = run_cmd_s(["build", "/app/s/misc/examples/s/sum.s", "-o", "/tmp/s_sum_cmd_s"])
        self.assertEqual(result.exit_code, 0)

        run = subprocess.run(
            ["/tmp/s_sum_cmd_s"],
            cwd="/app/s/src",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout.strip(), "5050")

    def test_native_runner_build_sum_binary_output(self) -> None:
        build_runner = subprocess.run(
            ["/app/s/misc/scripts/build_native_runner.sh", "/tmp/s_native_test"],
            cwd="/app",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(build_runner.returncode, 0, build_runner.stderr)

        build = subprocess.run(
            ["/tmp/s_native_test", "build", "/app/s/misc/examples/s/sum.s", "-o", "/tmp/s_sum_native_test"],
            cwd="/app",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(build.returncode, 0, build.stderr)

        run = subprocess.run(
            ["/tmp/s_sum_native_test"],
            cwd="/app/s/src",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout.strip(), "5050")

    def test_native_runner_build_cmd_s_launcher_binary_output(self) -> None:
        install = subprocess.run(
            ["/app/s/misc/scripts/install_selfhost_compiler_launcher.sh"],
            cwd="/app",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(install.returncode, 0, install.stderr)

        build_runner = subprocess.run(
            ["/app/s/misc/scripts/build_native_runner.sh", "/tmp/s_native_cmd_test"],
            cwd="/app",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(build_runner.returncode, 0, build_runner.stderr)

        build = subprocess.run(
            ["/tmp/s_native_cmd_test", "build", "/app/s/src/cmd/s/main.s", "-o", "/tmp/s_cmd_native_test"],
            cwd="/app",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(build.returncode, 0, build.stderr)

        run = subprocess.run(
            ["/tmp/s_cmd_native_test", "run", "/app/s/misc/examples/s/sum.s"],
            cwd="/app",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout.strip(), "5050")

    def test_selfhosted_launcher_runs_without_python_launcher(self) -> None:
        install = subprocess.run(
            ["/app/s/misc/scripts/install_selfhost_compiler_launcher.sh"],
            cwd="/app",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(install.returncode, 0, install.stderr)

        run = subprocess.run(
            ["/app/s/bin/s-selfhosted", "run", "/app/s/misc/examples/s/sum.s"],
            cwd="/app",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout.strip().splitlines()[-1], "5050")

    def test_s_native_runner_interprets_int_literal_shape(self) -> None:
        runner = Interpreter(parse_source(Path("/app/s/src/runtime/runner.s").read_text()))
        result = runner.call_function(
            "compileMessageForSource",
            [
                "package demo.literal\n\nuse std.io.println\n\nfunc main() -> int {\n    println(42);\n    0\n}\n"
            ],
        )
        self.assertEqual(result, ("Some", "42\n"))

    def test_s_native_runner_encodes_extended_ascii(self) -> None:
        runner = Interpreter(parse_source(Path("/app/s/src/runtime/runner.s").read_text()))
        result = runner.call_function("encodeBytes", ["@[]{}~"])
        self.assertEqual(result, "64, 91, 93, 123, 125, 126")
