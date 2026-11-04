#!/usr/bin/env python3
"""Standalone seed values must retain all 64 integer bits, including in graphs."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = '''package main
struct Number { int value }
func multiply(int value) int { return value * -3 }
func identity(int value) int { return value }
func number(int value) Number { return Number { value: value * -3 } }
func values(int value) int[] { result := value * -3; return int[]{result} }
func main() int {
    value := multiply(2431651138594789708)
    if to_string(value) != "-7294953415784369124" { return 1 }
    if to_string(identity(7294953415784369124)) != "7294953415784369124" { return 2 }
    if to_string(number(2431651138594789708).value) != "-7294953415784369124" { return 3 }
    if value >= 0 { return 4 }
    if to_string(value + 7294953415784369124) != "0" { return 5 }
    if to_string(value / -3) != "2431651138594789708" { return 6 }
    if to_string(value % -3) != "0" { return 7 }
    if to_string(9223372036854775807 + 1) != "-9223372036854775808" { return 8 }
    if to_string(values(2431651138594789708)[0]) != "-7294953415784369124" { return 9 }
    if to_string(7294953415784369124 - 1) != "7294953415784369123" { return 10 }
    if to_string(7294953415784369124 >> 4) != "455934588486523070" { return 11 }
    if to_string(7294953415784369124 & 255) != "228" { return 12 }
    if to_string((9223372036854775807 + 1) / -1) != "-9223372036854775808" { return 13 }
    if to_string((9223372036854775807 + 1) % -1) != "0" { return 14 }
    return 42
}
'''
with tempfile.TemporaryDirectory(prefix='s-seed-int64-') as directory:
    work = Path(directory)
    source, ir, binary = work / 'main.s', work / 'main.ir', work / 'main'
    source.write_text(SOURCE)
    environment = dict(os.environ, S_SOURCE_ROOT=str(ROOT))
    subprocess.run([str(ROOT / 'bin/s_seed'), '--compile-unit', str(ir), str(source)], check=True, timeout=30, env=environment)
    subprocess.run([str(ROOT / 'bin/s_seed'), '--emit-standalone-amd64', str(ir), str(binary)], check=True, timeout=30, env=environment)
    result = subprocess.run([str(binary)], timeout=10, capture_output=True)
    assert result.returncode == 42, (result.returncode, result.stderr)
    source.write_text('package main\nfunc main() int { return 7294953415784369124 }\n')
    subprocess.run([str(ROOT / 'bin/s_seed'), '--compile-unit', str(ir), str(source)], check=True, timeout=30, env=environment)
    subprocess.run([str(ROOT / 'bin/s_seed'), '--emit-standalone-amd64', str(ir), str(binary)], check=True, timeout=30, env=environment)
    result = subprocess.run([str(binary)], timeout=10, capture_output=True)
    assert result.returncode == (7294953415784369124 & 255), ('wide main return', result.returncode)
print('standalone seed full-width integer constants, arithmetic and aggregate escape: PASS')
