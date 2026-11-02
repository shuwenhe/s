#!/usr/bin/env python3
"""Keep library objects PIE-linkable and preserve values across C entry calls."""
from pathlib import Path
import os
import resource
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
COMPILER = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / 'bin/s_compiler'

def limits():
    resource.setrlimit(resource.RLIMIT_AS, (512 * 1024**2,) * 2)
    resource.setrlimit(resource.RLIMIT_CPU, (60, 60))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))

with tempfile.TemporaryDirectory(prefix='s-native-gc-object-') as directory:
    work = Path(directory)
    source = ROOT / 'test/native-bootstrap-diagnostic/native_gc_live_graph.s'
    obj, binary = work / 'graph.o', work / 'graph'
    subprocess.run([str(COMPILER), '--emit-native-object', str(source), str(obj)], check=True, timeout=60)
    runner = work / 'runner.c'
    runner.write_text('extern long s_native_entry(void);\nint main(void) { return s_native_entry() == 42 && s_native_entry() == 42 ? 0 : 1; }\n')
    subprocess.run([os.environ.get('CC', 'cc'), '-O2', '-Wall', '-Wextra', '-Werror', str(runner), str(obj), '-o', str(binary)], check=True)
    result = subprocess.run([str(binary)], preexec_fn=limits, capture_output=True, timeout=65)
    assert result.returncode == 0, (result.returncode, result.stderr.decode())
    escaped = ROOT / 'test/native-bootstrap-diagnostic/native_gc_object_escape.s'
    escape_obj, escape_binary = work / 'escape.o', work / 'escape'
    subprocess.run([str(COMPILER), '--emit-native-object', str(escaped), str(escape_obj)], check=True, timeout=60)
    runner.write_text('extern const long *s_native_entry(long);\nint main(void) { const long *saved=s_native_entry(0); const long *later=s_native_entry(2500000); return saved[0]==1 && saved[1]==42 && later[0]==1 && later[1]==2500000 ? 0 : 1; }\n')
    subprocess.run([os.environ.get('CC', 'cc'), '-O2', '-Wall', '-Wextra', '-Werror', str(runner), str(escape_obj), '-o', str(escape_binary)], check=True)
    result = subprocess.run([str(escape_binary)], preexec_fn=limits, capture_output=True, timeout=65)
    assert result.returncode == 0, (result.returncode, result.stderr.decode())
print('native GC objects: default PIE link and repeated C entries and escaped arrays preserve lifetime within 512 MiB: PASS')
