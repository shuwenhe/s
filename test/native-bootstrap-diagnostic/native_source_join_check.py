#!/usr/bin/env python3
"""Catch quadratic source joining and changed file-boundary bytes in native code."""
from pathlib import Path
import resource
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
COMPILER = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / 'bin/s_compiler'


def limits():
    resource.setrlimit(resource.RLIMIT_AS, (64 * 1024**2,) * 2)
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


text = (ROOT / 'src/cmd/compile/internal/compiler/main.s').read_text()
helpers = text[text.index('func canonical_join_sources('):text.index('func handle_compile_unit(')]

with tempfile.TemporaryDirectory(prefix='s-source-join-') as directory:
    work = Path(directory)
    source = work / 'join.s'
    source.write_text('''package main
''' + helpers + '''
func main() int {
    empty := string[]()
    if canonical_join_sources(empty) != "" { return 1 }
    empty.push("")
    if canonical_join_sources(empty) != "\\n" { return 2 }
    empty.push("b\\n")
    if canonical_join_sources(empty) != "\\nb\\n\\n" { return 3 }
    empty.push("c")
    if canonical_join_sources(empty) != "\\nb\\n\\nc\\n" { return 4 }
    empty.push("d")
    if canonical_join_sources(empty) != "\\nb\\n\\nc\\nd\\n" { return 5 }
    chunk := "z"
    i := 0
    for i < 13 { chunk = chunk + chunk; i = i + 1 }
    inputs := string[]()
    i = 0
    for i < 268 { inputs.push(chunk); i = i + 1 }
    joined := canonical_join_sources(inputs)
    if len(joined) != 2195724 { return 6 }
    i = 0
    for i < 268 {
        if __host_char_at(joined, i * 8193) != "z" { return 7 }
        if __host_char_at(joined, i * 8193 + 8192) != "\\n" { return 8 }
        i = i + 1
    }
    return 42
}
extern "intrinsic" func __host_char_at(string source, int index) string
''')
    assembly, binary = work / 'join.sasm', work / 'join'
    subprocess.run([str(COMPILER), '--compile-unit', str(assembly), str(source)], check=True, timeout=60)
    subprocess.run([str(COMPILER), '--emit-bin', str(assembly), str(binary)], check=True, timeout=60)
    result = subprocess.run([str(binary)], preexec_fn=limits, capture_output=True, timeout=30)
    assert result.returncode == 42, (result.returncode, result.stderr.decode())
print('native source joining: exact boundary bytes and 268 x 8 KiB under 64 MiB: PASS')
