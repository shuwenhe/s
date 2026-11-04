#!/usr/bin/env python3
"""Wide integer loops must reclaim temporary boxes with constant live storage."""
from pathlib import Path
import os
import resource
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = '''package main
func spin() int {
    value := 7294953415784369124
    i := 0
    for i < 20000000 { value = value + 1; i = i + 1 }
    return value - 7294953415784369124
}
func main() int {
    if spin() == 20000000 { return 42 }
    return 1
}
'''


def limits():
    resource.setrlimit(resource.RLIMIT_DATA, (128 * 1024**2,) * 2)
    resource.setrlimit(resource.RLIMIT_CPU, (30, 30))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


with tempfile.TemporaryDirectory(prefix='s-seed-int64-memory-') as directory:
    work = Path(directory)
    source, ir, binary = work / 'main.s', work / 'main.ir', work / 'main'
    source.write_text(SOURCE)
    environment = dict(os.environ, S_SOURCE_ROOT=str(ROOT))
    subprocess.run([str(ROOT / 'bin/s_seed'), '--compile-unit', str(ir), str(source)], check=True, timeout=30, env=environment)
    subprocess.run([str(ROOT / 'bin/s_seed'), '--emit-standalone-amd64', str(ir), str(binary)], check=True, timeout=30, env=environment)
    result = subprocess.run([str(binary)], timeout=35, capture_output=True, preexec_fn=limits)
    assert result.returncode == 42, (result.returncode, result.stderr)
print('standalone seed wide integer loop: 20 million iterations within 128 MiB: PASS')
