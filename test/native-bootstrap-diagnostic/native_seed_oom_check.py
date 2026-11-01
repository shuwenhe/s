#!/usr/bin/env python3
"""Standalone seed emitters bound local storage and fail cleanly on exhaustion."""

import os
from pathlib import Path
import resource
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SEED = ROOT / "bin/s_seed"
MEMORY_LIMIT = 256 * 1024 * 1024


def limit_memory(limit=MEMORY_LIMIT):
    resource.setrlimit(resource.RLIMIT_AS, (limit, limit))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


class StandaloneMemoryUsage(unittest.TestCase):
    def test_emitters_grow_local_storage_within_two_gibibytes(self):
        with tempfile.TemporaryDirectory(prefix="s-seed-slots-") as directory:
            work = Path(directory)
            source = work / "main.s"
            bindings = ["v0 := 1"]
            bindings += [f"v{i} := v{i - 1} + 1" for i in range(1, 80)]
            source.write_text(
                "package main\nfunc main() int {\n"
                + "\n".join(bindings)
                + "\nreturn v79 - 38\n}\n"
            )
            ir = work / "main.ir"
            subprocess.run(
                [str(SEED), "--compile-native-unit", str(ir), str(source)],
                check=True,
                capture_output=True,
                timeout=30,
            )
            env = dict(os.environ, S_SOURCE_ROOT=str(ROOT))
            for mode in ("--emit-standalone-amd64", "--emit-standalone-amd64-obj"):
                with self.subTest(mode=mode):
                    output = work / mode[2:]
                    result = subprocess.run(
                        [str(SEED), mode, str(ir), str(output)],
                        capture_output=True,
                        env=env,
                        preexec_fn=lambda: limit_memory(2 * 1024 * 1024 * 1024),
                        timeout=30,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr.decode())
                    self.assertEqual(output.read_bytes()[:4], b"\x7fELF")
                    if mode == "--emit-standalone-amd64":
                        executed = subprocess.run([str(output)], timeout=10)
                        self.assertEqual(executed.returncode, 42)

    def test_emitters_preserve_output_and_report_out_of_memory(self):
        with tempfile.TemporaryDirectory(prefix="s-seed-oom-") as directory:
            work = Path(directory)
            source = work / "main.s"
            source.write_text("package main\nfunc main() int { return 42 }\n")
            ir = work / "main.ir"
            subprocess.run(
                [str(SEED), "--compile-native-unit", str(ir), str(source)],
                check=True,
                capture_output=True,
                timeout=30,
            )
            env = dict(os.environ, S_SOURCE_ROOT=str(ROOT))
            for mode in ("--emit-standalone-amd64", "--emit-standalone-amd64-obj"):
                with self.subTest(mode=mode):
                    output = work / "output"
                    sentinel = b"preserve existing output\n"
                    output.write_bytes(sentinel)
                    result = subprocess.run(
                        [str(SEED), mode, str(ir), str(output)],
                        capture_output=True,
                        env=env,
                        preexec_fn=limit_memory,
                        timeout=30,
                    )
                    self.assertEqual(output.read_bytes(), sentinel)
                    self.assertGreater(result.returncode, 0, result.stderr.decode())
                    self.assertIn(b"out of memory", result.stderr.lower())


if __name__ == "__main__":
    unittest.main()
