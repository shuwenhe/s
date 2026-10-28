#!/usr/bin/env python3
"""Consume contiguous argument copies, retaining earlier evaluation snapshots."""
from pathlib import Path
import resource
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def limits():
    resource.setrlimit(resource.RLIMIT_AS, (64 * 1024**2,) * 2)
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


with tempfile.TemporaryDirectory(prefix='s-argument-region-') as directory:
    work = Path(directory)
    source = work / 'main.s'
    source.write_text('''package main
state := int[]()
func read(int[] first, int[] second, int marker) int {
    first[0] = first[0] + marker
    return first[0] + second[0]
}
func mutate() int { state[0] = 7; return 7 }
func ordered(int[] before, int after) int {
    if before[0] == 42 && after == 7 { return 42 }
    return 1
}
func main() int {
    state.push(0)
    values := make(int[], 16000)
    values[0] = 21
    i := 0
    while i < 1000 {
        state[0] = i
        if read(values, values, 0) != 42 || values[0] != 21 { return 2 }
        i = i + 1
    }
    if state[0] != 999 { return 3 }
    state[0] = 42
    if ordered(state, mutate()) != 42 || state[0] != 7 { return 4 }
    return 42
}
''')
    ir, binary = work / 'main.ir', work / 'main'
    subprocess.run([str(ROOT / 'bin/s_seed'), '--compile-native-unit', str(ir), str(source)], check=True)
    subprocess.run([str(ROOT / 'bin/s_seed'), '--emit-standalone-amd64', str(ir), str(binary)],
                   cwd=ROOT, check=True)
    result = subprocess.run([str(binary)], preexec_fn=limits, capture_output=True, timeout=20)
    assert result.returncode == 42, (result.returncode, result.stderr.decode())

print('contiguous argument cleanup, global mutation and nested evaluation snapshots under 64 MiB: PASS')
