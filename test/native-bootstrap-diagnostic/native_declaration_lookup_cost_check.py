#!/usr/bin/env python3
"""Nominal lookup must inspect metadata without copying declaration payloads."""
from pathlib import Path
import re, struct, subprocess, tempfile
ROOT = Path(__file__).resolve().parents[2]
SEED = ROOT / 'bin/s_seed'
def function(text, name):
    start = text.index('func ' + name + '(')
    following = re.search(r'^func |^struct |^enum ', text[start + 5:], re.M)
    return text[start:start + 5 + following.start()] if following else text[start:]
def run(args):
    subprocess.run(list(map(str, args)), cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
with tempfile.TemporaryDirectory(prefix='s-declaration-lookup-') as directory:
    work = Path(directory)
    semantic = (ROOT / 'src/cmd/compile/internal/semantic/semantic.s').read_text()
    enums = (ROOT / 'src/cmd/compile/internal/semantic/canonical_enum.s').read_text()
    fixture = '''package main
import ("compile.internal.typesys"; "std.prelude")
enum declaration_kind { function_kind, struct_kind, enum_kind }
struct declaration_ref { int[] fields; int[] variants; string[] generics; string package_path; declaration_kind kind; string path }
'''
    for text, name in [(semantic,'semantic_starts_with'), (semantic,'canonical_record_index'), (enums,'canonical_enum_index')]:
        fixture += function(text, name)
    fixture += '''
func main() int {
    payload := make(int[], 200)
    declarations := declaration_ref[]()
    i := 0
    while i < 50 {
        declarations.push(declaration_ref { fields: payload, variants: payload, package_path: "other", kind: declaration_kind.function_kind, path: "skip" })
        i = i + 1
    }
    declarations.push(declaration_ref { fields: payload, package_path: "a", kind: declaration_kind.struct_kind, path: "Record" })
    declarations.push(declaration_ref { fields: payload, package_path: "b", kind: declaration_kind.struct_kind, path: "Record" })
    declarations.push(declaration_ref { variants: payload, package_path: "a", kind: declaration_kind.enum_kind, path: "Choice" })
    declarations.push(declaration_ref { variants: payload, package_path: "b", kind: declaration_kind.enum_kind, path: "Choice" })
    i = 0
    while i < 30 {
        if canonical_record_index("a.Record", declarations) != 50 { return 1 }
        if canonical_enum_index("b.Choice[int]", declarations) != 53 { return 2 }
        if canonical_record_index("Record", declarations) != -1 { return 3 }
        if canonical_enum_index("Choice", declarations) != -1 { return 4 }
        if canonical_record_index("Missing", declarations) != -1 { return 5 }
        i = i + 1
    }
    return 42
}
'''
    (work / 'main.s').write_text(fixture)
    sources = [ROOT / 'src/prelude/prelude.s', ROOT / 'src/cmd/compile/internal/typesys/typesys.s', ROOT / 'src/cmd/compile/internal/typesys/canonical_type.s']
    ir, assembly = work / 'main.ir', work / 'main.S'
    run([SEED, '--compile-native-unit', ir, work / 'main.s', *sources])
    run([SEED, '--emit-standalone-amd64-asm', ir, assembly])
    runtime = (ROOT / 'src/runtime/selfhost_linux_amd64.S').read_text()
    runtime = runtime.replace('.Lrecord_snapshot_allocate:\n', '.Lrecord_snapshot_allocate:\n    incq snapshot_count(%rip)\n', 1)
    runtime = runtime.replace('    call s_main\n', '''    call s_main
    push %rax
    mov $1, %edi
    lea snapshot_count(%rip), %rsi
    mov $8, %edx
    mov $1, %eax
    syscall
    pop %rax
''', 1)
    runtime += '\n.section .bss\n.balign 8\nsnapshot_count: .quad 0\n'
    (work / 'runtime.S').write_text(runtime)
    for name in ('main', 'runtime'):
        run(['as', '--64', '-o', work / f'{name}.o', work / f'{name}.S'])
    run(['ld', '-static', '--gc-sections', '-T', ROOT / 'src/runtime/linker/nostdlib.ld', '-o', work / 'main', work / 'runtime.o', work / 'main.o'])
    result = subprocess.run([str(work / 'main')], capture_output=True, timeout=30)
    assert result.returncode == 42, (result.returncode, result.stderr)
    snapshots, = struct.unpack('<Q', result.stdout)
    assert snapshots < 300, f'150 nominal lookups copied {snapshots} aggregates'
    print(f'qualified, ambiguous and missing nominal lookups: {snapshots} snapshots: PASS')
