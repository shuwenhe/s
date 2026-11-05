#!/usr/bin/env python3
"""Build and execute the complete documented native tour through the driver."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='s-native-tutorial-') as directory:
    binary = Path(directory) / 'tour'
    # This directory contains independent executable fixtures sharing package main.
    source = Path(directory) / 'main.s'
    source.write_bytes((ROOT / 'test/native-bootstrap-diagnostic/native_tour.s').read_bytes())
    subprocess.run(['sh', str(ROOT / 'misc/scripts/s-driver.sh'), 'build',
                    str(source), '-o', str(binary)], check=True, timeout=60)
    subprocess.run(['sh', str(ROOT / 'misc/scripts/verify_true_selfhost.sh'), str(binary)], check=True, timeout=10)
    result = subprocess.run([str(binary)], capture_output=True, timeout=5)
    assert result.returncode == 42, (result.returncode, result.stderr.decode())
print('documented native tour: array snapshots, receivers, generics, tuples and enums: PASS')
