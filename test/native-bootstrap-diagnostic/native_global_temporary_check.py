#!/usr/bin/env python3
"""Global diagnostics must not retain dead by-value argument snapshots."""
from pathlib import Path
import resource
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def limits():
    resource.setrlimit(resource.RLIMIT_AS, (64 * 1024**2,) * 2)
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


with tempfile.TemporaryDirectory(prefix='s-global-temporary-') as directory:
    work = Path(directory)
    source = work / 'main.s'
    source.write_text('''package main
notes := int[]()
func diagnose(int[] values) int {
    notes.push(values[0])
    values[0] = 7
    return 42
}
func relay(int[] values) int { return diagnose(values) }
func main() int {
    values := make(int[], 16000)
    values[0] = 42
    i := 0
    while i < 1000 {
        if relay(values) != 42 { return 1 }
        if values[0] != 42 { return 2 }
        i = i + 1
    }
    if len(notes) != 1000 || notes[0] != 42 || notes[999] != 42 { return 3 }
    return 42
}
''')
    ir = work / 'main.ir'
    binary = work / 'main'
    subprocess.run([str(ROOT / 'bin/s_seed'), '--compile-native-unit', str(ir), str(source)], check=True)
    subprocess.run([str(ROOT / 'bin/s_seed'), '--emit-standalone-amd64', str(ir), str(binary)],
                   cwd=ROOT, check=True)
    result = subprocess.run([str(binary)], preexec_fn=limits, capture_output=True, timeout=20)
    assert result.returncode == 42, (result.returncode, result.stderr.decode())
    source.write_text('''package main
values := string[][]()
func change() int { values[0][0] = "new" + "value"; return 0 }
func main() int {
    row := string[]()
    row.push("old")
    values.push(row)
    change()
    if values[0][0] != "newvalue" { return 2 }
    return 42
}
''')
    subprocess.run([str(ROOT / 'bin/s_seed'), '--compile-native-unit', str(ir), str(source)], check=True)
    subprocess.run([str(ROOT / 'bin/s_seed'), '--emit-standalone-amd64', str(ir), str(binary)], cwd=ROOT, check=True)
    result = subprocess.run([str(binary)], preexec_fn=limits, capture_output=True, timeout=20)
    assert result.returncode == 42, (result.returncode, result.stderr.decode())

print('global diagnostic promotion and private argument snapshots under 64 MiB: PASS')
