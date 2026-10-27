#!/usr/bin/env python3
"""A pure call may reclaim its final private argument snapshot, never earlier ARGs."""
import os
from pathlib import Path
import resource
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
seed = Path(os.environ.get('S_SEED_COMPILER', str(root / 'bin/s_seed')))


def limits():
    resource.setrlimit(resource.RLIMIT_AS, (64 * 1024 * 1024,) * 2)
    resource.setrlimit(resource.RLIMIT_CPU, (20, 20))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def run(source, work, name):
    path, ir, binary = (work / (name + suffix) for suffix in ('.s', '.ir', ''))
    path.write_text(source)
    subprocess.run([str(seed), '--compile-native-unit', str(ir), str(path)], cwd=root, check=True)
    subprocess.run([str(seed), '--emit-standalone-amd64', str(ir), str(binary)], cwd=root, check=True)
    executed = subprocess.run([str(binary)], capture_output=True, preexec_fn=limits, timeout=25)
    assert executed.returncode == 42, (
        f'{name}: exit={executed.returncode}, stderr={executed.stderr!r}')


with tempfile.TemporaryDirectory(prefix='s-call-argument-region-') as directory:
    work = Path(directory)
    run('''package main
counter := 0
func consume(int[] values) int { return len(values) }
func main() int {
    values := make(int[], 131072)
    i := 0
    while i < 160 {
        counter = counter + 1
        if consume(values) != 131072 { return 1 }
        i = i + 1
    }
    if counter != 160 { return 2 }
    return 42
}
''', work, 'bounded-impure-caller')
    print('160 MiB of pure callee argument snapshots reclaimed under 64 MiB: PASS')
    run('''package main
counter := 0
func mutate(int[]* values) int { values[0] = 9; counter = counter + 1; return 7 }
func choose(int[] before, int marker) int {
    if before[0] != 1 || marker != 7 { return 1 }
    return 42
}
func main() int {
    values := int[] { 1, 2 }
    answer := choose(values, mutate(values*))
    if values[0] != 9 || counter != 1 { return 2 }
    return answer
}
''', work, 'argument-evaluation-timing')
    print('earlier ARG snapshot keeps evaluation-time contents across later mutation: PASS')
    run('''package main
struct packet { int[] data }
counter := 0
func change(packet value) packet { value.data[0] = 9; return value }
func consume(int[] values) int { return len(values) }
func main() int {
    original := packet { data: int[] { 1, 2, 3 } }
    returned := change(original)
    i := 0
    while i < 100 {
        counter = counter + 1
        if consume(original.data) != 3 { return 1 }
        i = i + 1
    }
    if original.data[0] != 1 || returned.data[0] != 9 || returned.data[2] != 3 { return 2 }
    original.data[1] = 7
    if returned.data[1] != 2 { return 3 }
    return 42
}
''', work, 'returned-graph-lifetime')
    print('promoted returned graph survives later calls; by-value mutation stays isolated: PASS')
