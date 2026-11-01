#!/usr/bin/env python3
"""Global root replacement need not copy read-only arguments; mutation still does."""
from pathlib import Path
import resource
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SEED = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / "bin/s_seed"


def run(command):
    subprocess.run(command, cwd=ROOT, check=True)


def limits():
    resource.setrlimit(resource.RLIMIT_AS, (128 * 1024**2,) * 2)
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


with tempfile.TemporaryDirectory(prefix="s-global-readonly-") as directory:
    work = Path(directory)
    source = work / "main.s"
    source.write_text('''package main
struct item { int number }
notes := int[]()
shared := item[]()
func inspect(item[] values, int marker) int {
    notes.push(marker)
    return values[0].number
}
func relay(item[] values, int marker) int { return inspect(values, marker) }
func replace(item[] before) int {
    replacement := item { number: 7 }
    shared = [replacement];
    return before[0].number
}
func grow(item[] before) int {
    shared.push(item { number: 8 })
    return len(before)
}
func mutate(item[] before) int {
    shared[0].number = 9
    return before[0].number
}
func relay_mutation(item[] before) int { return mutate(before) }
func literal_mutation(item[] before) int {
    [shared][0][0].number = 12
    return before[0].number
}
func private_change(item[] values) int {
    notes.push(0)
    values[0].number = 99
    return values[0].number
}
func retain(item[] values) item[] { notes.push(0); return values }
func main() int {
    first := item { number: 42 }
    second := item { number: 3 }
    values := [first, second];
    i := 0
    while i < 500 {
        if relay(values, i) != 42 { return 1 }
        i = i + 1
    }
    if len(notes) != 500 || notes[0] != 0 || notes[499] != 499 { return 2 }
    shared.push(item { number: 42 })
    if replace(shared) != 42 || shared[0].number != 7 { return 3 }
    if grow(shared) != 1 || len(shared) != 2 { return 4 }
    if relay_mutation(shared) != 7 || shared[0].number != 9 { return 5 }
    if private_change(values) != 99 || values[0].number != 42 { return 6 }
    saved := retain(values)
    saved[0].number = 11
    if values[0].number != 42 { return 7 }
    if literal_mutation(shared) != 9 || shared[0].number != 12 { return 8 }
    return 42
}
''')
    ir, assembly = work / "main.ir", work / "main.S"
    run([str(SEED), "--compile-native-unit", str(ir), str(source)])
    run([str(SEED), "--emit-standalone-amd64-asm", str(ir), str(assembly)])
    runtime = (ROOT / "src/runtime/selfhost_linux_amd64.S").read_text()
    runtime = runtime.replace(
        ".Lrecord_snapshot_allocate:\n",
        ".Lrecord_snapshot_allocate:\n    incq snapshot_count(%rip)\n", 1)
    runtime = runtime.replace("    call s_main\n", '''    call s_main
    push %rax
    mov $1, %edi
    lea snapshot_count(%rip), %rsi
    mov $8, %edx
    mov $1, %eax
    syscall
    pop %rax
''', 1)
    runtime += "\n.section .bss\n.balign 8\nsnapshot_count: .quad 0\n"
    (work / "runtime.S").write_text(runtime)
    for name in ("main", "runtime"):
        run(["as", "--64", "-o", str(work / f"{name}.o"), str(work / f"{name}.S")])
    binary = work / "main"
    run(["ld", "-static", "--gc-sections", "-T", str(ROOT / "src/runtime/linker/nostdlib.ld"),
         "-o", str(binary), str(work / "runtime.o"), str(work / "main.o")])
    result = subprocess.run([str(binary)], capture_output=True, preexec_fn=limits, timeout=15)
    assert result.returncode == 42, (result.returncode, result.stderr)
    assert len(result.stdout) == 8, result.stdout
    snapshots, = struct.unpack("<Q", result.stdout)
    assert snapshots < 100, f"500 globally logging reads triggered {snapshots} aggregate snapshots"
    print(f"global logging/replacement: {snapshots} snapshots; aliased global/local mutation and returned copies: PASS")
