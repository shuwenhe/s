from __future__ import annotations

from pathlib import Path
import os
import subprocess

from compiler.ast import SourceFile
from compiler.internal.ir import MIRProgram, MIRWriteOp, lower_source
from compiler.internal.ssagen.asm import AsmProgram, BackendError, emit_program
from compiler.internal.ssagen.lowering import LoweredProgram, lower_program

BUILD_OUTPUT_ROOT = Path(os.environ.get("S_BUILD_OUTPUT_ROOT", "/app/tmp"))
PROJECT_ROOT = Path(os.environ.get("S_PROJECT_ROOT", "/app/s"))


def build_executable(source: SourceFile, output_path: Path) -> None:
    BUILD_OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if source.package == "runtime.runner":
        _build_native_runner(output_path)
        return
    from compiler.internal.amd64 import arch_name as current_arch_name, link_program

    lowered = lower_program(lower_source(source), current_arch_name())
    link_program(lowered, output_path)


def _build_native_runner(output_path: Path) -> None:
    template = (PROJECT_ROOT / "src/cmd/compiler/backend_elf64_runner_bootstrap.c").resolve()
    try:
        subprocess.run(
            ["cc", "-O2", "-std=c11", str(template), "-o", str(output_path)],
            check=True,
        )
    except subprocess.CalledProcessError as exc:
        raise BackendError(f"native runner bootstrap failed with exit code {exc.returncode}") from exc


__all__ = [
    "AsmProgram",
    "BackendError",
    "BUILD_OUTPUT_ROOT",
    "LoweredProgram",
    "MIRProgram",
    "MIRWriteOp",
    "build_executable",
    "emit_program",
    "lower_program",
]
