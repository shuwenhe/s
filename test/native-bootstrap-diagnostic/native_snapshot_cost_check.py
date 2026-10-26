#!/usr/bin/env python3
"""Count actual aggregate snapshots; avoid noisy wall-clock performance assertions."""
from pathlib import Path
import resource
import struct
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]

def run(command, **kwargs):
    return subprocess.run(command, check=True, cwd=root, **kwargs)

def limits():
    resource.setrlimit(resource.RLIMIT_AS, (128 * 1024 * 1024,) * 2)
    resource.setrlimit(resource.RLIMIT_CPU, (10, 10))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))

with tempfile.TemporaryDirectory(prefix='s-snapshot-cost-') as directory:
    work = Path(directory)
    source = work / 'main.s'
    source.write_text('''package main
struct item { int number }
func main() int {
    first := item { number: 42 }
    second := item { number: 7 }
    values := [first, second];
    i := 0
    total := 0
    while i < 2000 {
        total = total + len(values)
        i = i + 1
    }
    if total != 4000 { return 1 }
    copy := values
    copy[0].number = 99
    if values[0].number != 42 { return 2 }
    return values[0].number
}
''')
    ir = work / 'main.ir'
    asm = work / 'main.S'
    run([str(root / 'bin/s_seed'), '--compile-native-unit', str(ir), str(source)])
    run([str(root / 'bin/s_seed'), '--emit-standalone-amd64-asm', str(ir), str(asm)])
    runtime = (root / 'src/runtime/selfhost_linux_amd64.S').read_text()
    runtime = runtime.replace('.Lrecord_snapshot_allocate:\n',
                              '.Lrecord_snapshot_allocate:\n    incq snapshot_count(%rip)\n', 1)
    runtime = runtime.replace('    call s_main\n', '''    call s_main
    push %rax
    mov $1, %edi
    lea snapshot_count(%rip), %rsi
    mov $8, %edx
    mov $1, %eax
    syscall
    pop %rax
''', 1)
    runtime += '\n.section .bss\n.balign 8\nsnapshot_count: .quad 0\n'
    (work / 'runtime.S').write_text(runtime)
    for name in ('main', 'runtime'):
        run(['as', '--64', '-o', str(work / f'{name}.o'), str(work / f'{name}.S')])
    binary = work / 'program'
    run(['ld', '-static', '--gc-sections', '-T', str(root / 'src/runtime/linker/nostdlib.ld'),
         '-o', str(binary), str(work / 'runtime.o'), str(work / 'main.o')])
    result = subprocess.run([str(binary)], capture_output=True, preexec_fn=limits, timeout=15)
    assert result.returncode == 42, f'wrong value/copy semantics: {result.returncode}, {result.stderr!r}'
    assert len(result.stdout) == 8, result.stdout
    count, = struct.unpack('<Q', result.stdout)
    assert count < 100, f'2000 len calls triggered {count} aggregate snapshots (expected <100)'
    print(f'2000 aggregate len calls: {count} snapshots; independent value mutation preserved: PASS')
