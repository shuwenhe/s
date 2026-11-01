#!/usr/bin/env python3
"""Bound real native compilation of independent packages sharing local names."""
from pathlib import Path
import os
import resource
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
COMPILER = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / 'bin/s_compiler'


def limits():
    resource.setrlimit(resource.RLIMIT_AS, (512 * 1024**2,) * 2)
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def compile_unit(sources, artifact, *, valid):
    start = time.monotonic()
    peak = 0
    with tempfile.TemporaryFile(mode='w+') as log:
        process = subprocess.Popen(
            [str(COMPILER), '--compile-unit', str(artifact), *map(str, sources)],
            cwd=ROOT, env=dict(os.environ, S_SOURCE_ROOT=str(ROOT)),
            stdout=log, stderr=log, preexec_fn=limits,
        )
        while process.poll() is None:
            try:
                status = Path(f'/proc/{process.pid}/status').read_text()
                peak = max(peak, next(int(line.split()[1]) for line in status.splitlines()
                                      if line.startswith('VmRSS:')))
            except (FileNotFoundError, StopIteration):
                pass
            if time.monotonic() - start > 20:
                process.kill()
                process.wait()
                raise AssertionError('multi-package compilation exceeded 20 seconds')
            time.sleep(0.01)
        log.seek(0)
        output = log.read()
    if valid:
        assert process.returncode == 0, (process.returncode, output)
        assert artifact.read_text().startswith('# S-NATIVE-AMD64-V1\n')
    else:
        assert process.returncode != 0, 'same-package duplicate was accepted'
        assert 'e3010' in output, output
    return time.monotonic() - start, peak


with tempfile.TemporaryDirectory(prefix='s-multi-package-cost-') as directory:
    work = Path(directory)
    entry = work / 'main.s'
    entry.write_text('package main\nfunc main() int { return 42 }\n')
    modules = []
    for index in range(32):
        source = work / f'module{index}.s'
        source.write_text(f'package module{index}\nfunc common() int {{ return {index} }}\n')
        modules.append(source)
    artifact = work / 'program.sasm'
    for count in (8, 16, 32):
        elapsed, peak = compile_unit([entry, *modules[:count]], artifact, valid=True)
        print(f'{count + 1} modules: {elapsed:.3f}s, sampled peak RSS {peak / 1024:.1f} MiB')
    binary = work / 'program'
    subprocess.run([str(COMPILER), '--emit-bin', str(artifact), str(binary)], check=True,
                   cwd=ROOT, timeout=20)
    result = subprocess.run([str(binary)], timeout=5)
    assert result.returncode == 42, result.returncode
    duplicate = work / 'duplicate.s'
    duplicate.write_text('package module0\nfunc common() int { return 99 }\n')
    artifact.write_text('preserve existing output\n')
    compile_unit([entry, modules[0], duplicate], artifact, valid=False)
    assert artifact.read_text() == 'preserve existing output\n'

print('package-local function identity, bounded native compilation and duplicate rejection: PASS')
