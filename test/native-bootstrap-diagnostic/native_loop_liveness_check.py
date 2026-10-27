#!/usr/bin/env python3
"""Loop reclamation must discard dead values while preserving future uses."""
from pathlib import Path
import resource
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]


def limits():
    resource.setrlimit(resource.RLIMIT_AS, (64 * 1024 * 1024,) * 2)
    resource.setrlimit(resource.RLIMIT_CPU, (20, 20))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


with tempfile.TemporaryDirectory(prefix='s-loop-liveness-') as directory:
    work = Path(directory)
    payload = work / 'payload'
    payload.write_bytes(b'x' * (1024 * 1024))
    source = work / 'main.s'
    source.write_text('''package main
extern "intrinsic" func __host_read_source(string path) string
func main() int {
    args := host_args()
    retained := "before" + " loop"
    i := 0
    while i < 8 {
''' + ''.join(f'''        dead{j} := __host_read_source(args[1])
        if len(dead{j}) != 1048576 {{ return 1 }}
''' for j in range(16)) + '''        if i == 3 { retained = "after" + " loop" }
        i = i + 1
    }
    if retained != "after loop" { return 2 }
    return 42
}
''')
    ir, binary = work / 'main.ir', work / 'main'
    subprocess.run([str(root / 'bin/s_seed'), '--compile-native-unit', str(ir), str(source)],
                   check=True, cwd=root)
    subprocess.run([str(root / 'bin/s_seed'), '--emit-standalone-amd64', str(ir), str(binary)],
                   check=True, cwd=root)
    result = subprocess.run([str(binary), str(payload)], capture_output=True,
                            preexec_fn=limits, timeout=25)
    assert result.returncode == 42, (
        f'loop kept dead temporaries or lost live branch/exit values: '
        f'exit={result.returncode}, stderr={result.stderr!r}')
    print('128 MiB of dead loop values discarded under 64 MiB; exit value retained: PASS')

    # Growing evacuation buffers must not keep the previous scratch mapping
    # alive while mapping the replacement. Both are private between calls.
    source.write_text('''package main
extern "intrinsic" func __host_read_source(string path) string
func main() int {
    args := host_args()
    i := 0
    while i < 4 {
''' + ''.join(f'''        if i >= {j // 8} {{
            dead{j} := __host_read_source(args[1])
            if len(dead{j}) != 1048576 {{ return 1 }}
        }}
''' for j in range(32)) + '''        i = i + 1
    }
    return 42
}
''')
    subprocess.run([str(root / 'bin/s_seed'), '--compile-native-unit', str(ir), str(source)],
                   check=True, cwd=root)
    subprocess.run([str(root / 'bin/s_seed'), '--emit-standalone-amd64', str(ir), str(binary)],
                   check=True, cwd=root)

    def growing_limits():
        resource.setrlimit(resource.RLIMIT_AS, (80 * 1024 * 1024,) * 2)
        resource.setrlimit(resource.RLIMIT_CPU, (20, 20))
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))

    result = subprocess.run([str(binary), str(payload)], capture_output=True,
                            preexec_fn=growing_limits, timeout=25)
    assert result.returncode == 42, (
        f'evacuation scratch growth retained the old mapping: '
        f'exit={result.returncode}, stderr={result.stderr!r}')
    print('8/16/24/32 MiB loop allocations and scratch growth under 80 MiB: PASS')
