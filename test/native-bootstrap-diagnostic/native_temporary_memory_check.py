#!/usr/bin/env python3
"""Native compilation must finish modest inputs within a bounded address space."""
import os
from pathlib import Path
import resource
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
compiler = Path(os.environ.get('S_MEMORY_COMPILER', str(root / 'bin/s_compiler')))

def limits():
    resource.setrlimit(resource.RLIMIT_AS, (128 * 1024 * 1024,) * 2)
    resource.setrlimit(resource.RLIMIT_CPU, (30, 30))

with tempfile.TemporaryDirectory(prefix='s-memory-') as directory:
    work = Path(directory)
    for count in (40, 100):
        source = work / f'locals-{count}.s'
        source.write_text('package main\nfunc main() int {\n' + ''.join(
            f'    x{i} := {i}\n' for i in range(count)) + '    return 37\n}\n')
        output = work / f'locals-{count}'
        result = subprocess.run([str(compiler), 'build', str(source), '-o', str(output)],
                                cwd=root, preexec_fn=limits, capture_output=True,
                                text=True, timeout=40)
        assert result.returncode == 0, (
            f'{count} locals exceeded memory budget or failed: {result.returncode}\n{result.stderr}')
        assert output.is_file() and output.stat().st_size > 0
        executed = subprocess.run([str(output)], preexec_fn=limits, timeout=5)
        assert executed.returncode == 37, f'wrong native result: {executed.returncode}'
        print(f'{count} locals compiled under 128 MiB and executed correctly: PASS')
