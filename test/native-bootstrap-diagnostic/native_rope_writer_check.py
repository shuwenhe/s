#!/usr/bin/env python3
"""A public MIR dump must not exhaust the native Seed runtime's call stack."""
from pathlib import Path
import os
import resource
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
work = Path(tempfile.mkdtemp(prefix='s-native-rope-writer-'))
source = work / 'writer.s'
source.write_text('''package main
extern "intrinsic" func __host_write_text_file(string path, string text) int
func main() int {
    args := host_args()
    text := ""
    index := 0
    while index < 50000 {
        part := "ab"
        if index % 2 != 0 { part = "XYZ" }
        if args[1] == "right" { text = part + text }
        else if args[1] == "empty" { text = text + "" }
        else { text = text + part }
        index = index + 1
    }
    if __host_write_text_file(args[2], text) != 0 { return 7 }
    return 42
}
''')

def limits():
    resource.setrlimit(resource.RLIMIT_STACK, (256 * 1024, 256 * 1024))
    resource.setrlimit(resource.RLIMIT_AS, (128 * 1024**2, 128 * 1024**2))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))

try:
    seed = root / 'bin/s_seed'
    ir, binary = work / 'writer.ir', work / 'writer'
    subprocess.run([seed, '--compile-native-unit', ir, source], cwd=root, check=True)
    subprocess.run([seed, '--emit-standalone-amd64', ir, binary], cwd=root,
                   env=os.environ | {'S_SOURCE_ROOT': str(root)}, check=True)
    for direction in ['left', 'right', 'empty']:
        output = work / (direction + '.txt')
        result = subprocess.run([binary, direction, output], preexec_fn=limits, capture_output=True, timeout=60)
        (work / (direction + '.stderr.log')).write_bytes(result.stderr)
        assert result.returncode == 42, (direction, result.returncode, result.stderr)
        expected = b'' if direction == 'empty' else (b'XYZab' if direction == 'right' else b'abXYZ') * 25000
        assert output.read_bytes() == expected, direction
    for name, injection, expected in [('interrupted-write', 'write:error=EINTR:when=1', 42),
                                      ('no-write-progress', 'write:retval=0:when=1', 7),
                                      ('stack-growth-failure', 'mremap:error=ENOMEM:when=1', 7)]:
        output = work / (name + '.txt')
        trace = work / (name + '.trace')
        result = subprocess.run(['/usr/bin/strace', '-qq', '-e', 'trace=write,mmap,mremap,munmap',
                                 '-e', 'inject=' + injection, '-o', trace,
                                 binary, 'left', output], preexec_fn=limits, capture_output=True, timeout=60)
        assert result.returncode == expected, (name, result.returncode, result.stderr)
        if expected == 42:
            assert output.read_bytes() == b'abXYZ' * 25000
        else:
            assert output.read_bytes() == b''
            assert 'munmap(' in trace.read_text(), name
    print('native rope writer: 50000 left/right/empty nodes preserve exact bytes under 256 KiB stack: PASS')
    print('native rope writer: interrupted writes retry; zero progress and allocation failure return errors and release traversal mapping: PASS')
except BaseException:
    print('native rope writer failure artifacts:', work, flush=True)
    raise
else:
    shutil.rmtree(work)
