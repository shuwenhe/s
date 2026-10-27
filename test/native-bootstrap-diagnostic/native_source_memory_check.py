#!/usr/bin/env python3
"""Selfhost must read hundreds of small source files without retaining capacity.

A reader with package state keeps this test independent of optional region reclamation:
input loading itself must allocate in proportion to the bytes actually read.
"""
from pathlib import Path
import resource
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]


def limits():
    resource.setrlimit(resource.RLIMIT_AS, (64 * 1024 * 1024,) * 2)
    resource.setrlimit(resource.RLIMIT_CPU, (15, 15))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


with tempfile.TemporaryDirectory(prefix='s-source-memory-') as directory:
    work = Path(directory)
    source = work / 'reader.s'
    source.write_text('''package main
extern "intrinsic" func __host_read_source(string path) string
count := 0
bytes := 0
func read_sources(string[] paths) {
    i := 1
    while i < len(paths) {
        text := __host_read_source(paths[i])
        if text == "source payload\\n" {
            count = count + 1
            bytes = bytes + len(text)
        }
        i = i + 1
    }
}
func main() int {
    paths := host_args()
    read_sources(paths)
    if count != 264 { return 1 }
    if bytes != 3960 { return 2 }
    return 42
}
''')
    paths = []
    # Rejected reads must release their temporary mappings too. Directories
    # fail read(2); an oversized stream must fail the EOF probe, not truncate.
    oversized = work / 'oversized'
    with oversized.open('wb') as stream:
        stream.truncate(16777217)
    paths.extend([str(work)] * 20 + [str(oversized)] * 5)
    for i in range(264):
        path = work / f'source-{i}.s'
        path.write_bytes(b'source payload\n')
        paths.append(str(path))
    ir, binary = work / 'reader.ir', work / 'reader'
    subprocess.run([str(root / 'bin/s_seed'), '--compile-native-unit', str(ir), str(source)],
                   check=True, cwd=root)
    subprocess.run([str(root / 'bin/s_seed'), '--emit-standalone-amd64', str(ir), str(binary)],
                   check=True, cwd=root)
    result = subprocess.run([str(binary), *paths], preexec_fn=limits,
                            capture_output=True, timeout=20)
    assert result.returncode == 42, (
        f'264 source reads exceeded 64 MiB or lost contents: '
        f'exit={result.returncode}, stderr={result.stderr!r}')
    print('264 source files read with correct contents under 64 MiB: PASS')
