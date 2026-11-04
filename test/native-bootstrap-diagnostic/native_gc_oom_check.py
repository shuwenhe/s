#!/usr/bin/env python3
"""Native allocation exhaustion must take the defined exit, not fault or hang."""
from pathlib import Path
import resource
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def limits():
    resource.setrlimit(resource.RLIMIT_AS, (48 * 1024**2,) * 2)
    resource.setrlimit(resource.RLIMIT_CPU, (10, 10))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


with tempfile.TemporaryDirectory(prefix='s-native-gc-oom-') as directory:
    work = Path(directory)
    compiler = ROOT / 'bin/s_compiler'
    source = ROOT / 'test/native-bootstrap-diagnostic/native_gc_oom.s'
    assembly, binary = work / 'oom.sasm', work / 'oom'
    subprocess.run([str(compiler), '--compile-unit', str(assembly), str(source)], check=True, timeout=60)
    subprocess.run([str(compiler), '--emit-bin', str(assembly), str(binary)], check=True, timeout=60)
    result = subprocess.run([str(binary)], preexec_fn=limits, capture_output=True, timeout=15)
    assert result.returncode == 126, (result.returncode, result.stderr.decode())
print('native GC: retained string growth exhausts 48 MiB with defined exit 126: PASS')
