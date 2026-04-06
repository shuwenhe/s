from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import subprocess
import tempfile

from compiler.ast import SourceFile
from compiler.internal.ir import MIRProgram, MIRWriteOp, lower_source

BUILD_OUTPUT_ROOT = Path("/app/tmp")


class BackendError(Exception):
    pass


@dataclass
class WriteOp:
    fd: int
    text: str


@dataclass(frozen=True)
class MachineWriteOp:
    fd: int
    text: str


@dataclass(frozen=True)
class MachineExitOp:
    code: int


@dataclass(frozen=True)
class MachineOp:
    kind: str
    fd: int = 1
    text: str = ""
    code: int = 0


@dataclass(frozen=True)
class MachineProgram:
    entry_symbol: str
    ops: list[MachineOp]
    exit_code: int


def build_executable(source: SourceFile, output_path: Path) -> None:
    BUILD_OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if source.package == "runtime.runner":
        _build_native_runner(output_path)
        return
    machine = lower_program(lower_source(source), "amd64")
    emit_program(machine, output_path)


def lower_program(mir: MIRProgram, arch_name: str) -> MachineProgram:
    ops: list[MachineOp] = []
    for write in mir.writes:
        _append_write_op(ops, write)
    ops.append(MachineOp(kind="exit", code=mir.exit_code))
    return MachineProgram(entry_symbol=_entry_symbol(arch_name), ops=ops, exit_code=mir.exit_code)


def emit_program(program: MachineProgram, output_path: Path) -> None:
    BUILD_OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    asm = _emit_machine_asm(program)

    with tempfile.TemporaryDirectory(prefix="s-build-", dir=str(BUILD_OUTPUT_ROOT)) as tmp:
        workdir = Path(tmp)
        asm_path = workdir / "out.s"
        obj_path = workdir / "out.o"
        asm_path.write_text(asm)

        try:
            subprocess.run(["as", "-o", str(obj_path), str(asm_path)], check=True)
            subprocess.run(["ld", "-o", str(output_path), str(obj_path)], check=True)
        except subprocess.CalledProcessError as exc:
            raise BackendError(f"toolchain failed with exit code {exc.returncode}") from exc


def _build_native_runner(output_path: Path) -> None:
    template = Path("/app/s/src/cmd/compiler/backend_elf64_runner_bootstrap.c").resolve()
    try:
        subprocess.run(
            ["cc", "-O2", "-std=c11", str(template), "-o", str(output_path)],
            check=True,
        )
    except subprocess.CalledProcessError as exc:
        raise BackendError(f"native runner bootstrap failed with exit code {exc.returncode}") from exc


def _append_write_op(ops: list[MachineOp], write: MIRWriteOp) -> None:
    if write.fd == 2:
        ops.append(MachineOp(kind="stderr", fd=write.fd, text=write.text))
        return
    ops.append(MachineOp(kind="stdout", fd=write.fd, text=write.text))


def _entry_symbol(arch_name: str) -> str:
    if arch_name == "amd64":
        return "_start"
    return "_start"


def _emit_machine_asm(program: MachineProgram) -> str:
    ops, exit_code = program.ops, program.exit_code
    data_lines: list[str] = [".section .data"]
    text_lines: list[str] = [".section .text", f".global {program.entry_symbol}", f"{program.entry_symbol}:"]

    for index, op in enumerate(ops):
        if op.kind == "exit":
            continue
        label = f"message_{index}"
        encoded = op.text.encode("utf-8")
        payload = ", ".join(str(byte) for byte in encoded) if encoded else "0"
        data_lines.append(f"{label}:")
        data_lines.append(f"    .byte {payload}")
        text_lines.extend(
            [
                "    mov $1, %rax",
                f"    mov ${op.fd}, %rdi",
                f"    lea {label}(%rip), %rsi",
                f"    mov ${len(encoded)}, %rdx",
                "    syscall",
            ]
        )

    text_lines.extend(
        [
            "    mov $60, %rax",
            f"    mov ${exit_code}, %rdi",
            "    syscall",
        ]
    )
    return "\n".join(data_lines + [""] + text_lines + [""])
