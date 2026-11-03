#!/usr/bin/env python3
"""Exercise reclamation and retained native values through the production emitter."""
from pathlib import Path
import json
import resource
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
COMPILER = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / 'bin/s_compiler'

def limits(mebibytes):
    def apply():
        resource.setrlimit(resource.RLIMIT_AS, (mebibytes * 1024**2,) * 2)
        resource.setrlimit(resource.RLIMIT_CPU, (60, 60))
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    return apply

with tempfile.TemporaryDirectory(prefix='s-native-gc-test-') as directory:
    work = Path(directory)
    for name, mebibytes in [('churn', 128), ('roots', 128), ('live_graph', 512)]:
        source = ROOT / f'test/native-bootstrap-diagnostic/native_gc_{name}.s'
        assembly, binary = work / f'{name}.sasm', work / name
        subprocess.run([str(COMPILER), '--compile-unit', str(assembly), str(source)], check=True, timeout=60)
        subprocess.run([str(COMPILER), '--emit-bin', str(assembly), str(binary)], check=True, timeout=60)
        metrics = work / f'{name}.json'
        result = subprocess.run(['/usr/bin/time', '-q', '-f', '{"wall_seconds":%e,"user_seconds":%U,"system_seconds":%S,"max_rss_kb":%M}', '-o', str(metrics), str(binary)], preexec_fn=limits(mebibytes), capture_output=True, timeout=65)
        assert result.returncode == 42, (name, result.returncode, result.stderr.decode())
        print(f'native GC {name}: limit={mebibytes} MiB, ' + json.dumps(json.loads(metrics.read_text())))
print('native GC: reclamation, global/recursive/reference roots, snapshots and large live graph: PASS')
