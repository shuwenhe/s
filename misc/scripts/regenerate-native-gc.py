#!/usr/bin/env python3
"""Regenerate checked-in GC assembly and its canonical S emitter; --check is read-only."""
from pathlib import Path
import argparse
import json
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
runtime = root / 'src/runtime'
flags = ['-S', '-O2', '-ffreestanding', '-fno-builtin', '-fno-stack-protector', '-fPIE', '-mno-red-zone']
with tempfile.TemporaryDirectory(prefix='s-native-gc-') as directory:
    output = Path(directory) / 'native_gc.S'
    subprocess.run([os.environ.get('CC', 'gcc'), *flags, 'native_gc.c', '-o', str(output)], cwd=runtime, check=True)
    assembly = (runtime / 'native_gc_entry_amd64.S').read_text() + output.read_text()
# Seed IR operands have 1024-byte storage; leave room for serialization.
parts, chunk = [], ''
for line in assembly.splitlines(keepends=True):
    if len(json.dumps(chunk + line)) > 900:
        parts.append(chunk)
        chunk = ''
    chunk += line
if chunk:
    parts.append(chunk)
helper = ('func amd64_record_allocator() string {\n    return '
          + '\n        + '.join(json.dumps(part) for part in parts) + '\n}\n')
source = root / 'src/cmd/compile/internal/codegen/amd64_program.s'
text = source.read_text()
start = text.index('func amd64_record_allocator(')
end = text.index('\nfunc amd64_needs_arena', start)
updated = text[:start] + helper + text[end:]
if args.check:
    assert (runtime / 'native_gc_amd64.S').read_text() == assembly, 'GC assembly differs; use pinned GCC or regenerate'
    assert text == updated, 'S emitter differs from GC assembly'
    print('native GC assembly and S emitter match their preserved runtime sources: PASS')
else:
    (runtime / 'native_gc_amd64.S').write_text(assembly)
    source.write_text(updated)
