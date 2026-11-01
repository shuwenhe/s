#!/usr/bin/env python3
"""Count package lookups while collecting real native MIR record layouts."""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
ir = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / '.bootstrap/compiler/compiler.ir'
with tempfile.TemporaryDirectory(prefix='s-record-collection-cost-') as directory:
    work = Path(directory)
    output = []
    function = ''
    pending = False
    for line in ir.read_text().splitlines():
        if line.startswith('FUNC_BEGIN|'):
            function = line.split('|')[1]
            pending = function in ('program_collect_records', 'program_item_package')
        elif pending and not line.startswith('PARAM|'):
            label = 'begin' if function == 'program_collect_records' else 'package'
            output.extend([f'ARG|"record-cost: {label}"|_|_', 'CALL|__record_cost_trace|eprintln|1'])
            pending = False
        if function == 'program_collect_records' and line.startswith('RET|'):
            output.extend(['ARG|"record-cost: end"|_|_', 'CALL|__record_cost_trace|eprintln|1'])
        output.append(line)
    (work / 'compiler.ir').write_text('\n'.join(output) + '\n')
    compiler = work / 'compiler'
    subprocess.run([str(root / 'bin/s_seed'), '--emit-standalone-amd64', str(work / 'compiler.ir'), str(compiler)], cwd=root, check=True, timeout=90)
    size = 32
    prefix = 'package main\n'
    prefix += ''.join(f'struct Record{i} {{ int value }}\n' for i in range(size))
    prefix += ''.join(f'func helper{i}(int value) int {{ return value + 1 }}\n' for i in range(size))
    red = 'package red\nstruct Leaf { int value }\nstruct Wrapper { Leaf leaf }\nenum Message { some(Wrapper), none }\n'
    blue = 'package blue\nstruct Leaf { bool value }\nstruct Wrapper { Leaf leaf }\nenum Message { some(Wrapper), none }\n'
    main = """package main
func main() int {
    a := red.Message.some(red.Wrapper { leaf: red.Leaf { value: 40 } })
    b := blue.Message.some(blue.Wrapper { leaf: blue.Leaf { value: true } })
    score := switch a { red.Message.some(v): v.leaf.value, red.Message.none: 0, }
    ready := switch b { blue.Message.some(v): v.leaf.value, blue.Message.none: false, }
    if ready { return score + 2 }; return 1
}
"""
    for order, declarations in enumerate([red + blue, blue + red]):
        (work / 'main.s').write_text(prefix + declarations + main)
        artifact = work / f'main-{order}.sasm'
        result = subprocess.run([str(compiler), '--compile-unit', str(artifact), str(work / 'main.s')], cwd=root, capture_output=True, text=True, check=True, timeout=60)
        scope = result.stderr.split('record-cost: begin\n', 1)[1].split('record-cost: end\n', 1)[0]
        lookups = scope.count('record-cost: package')
        records = size + 6  # Ordinary records and synthesized payload records.
        assert lookups <= records * 3, f'repeated AST rescans: {lookups} package lookups for {records} records'
        binary = work / f'main-{order}'
        subprocess.run([str(compiler), '--emit-bin', str(artifact), str(binary)], check=True, timeout=30)
        assert subprocess.run([str(binary)], timeout=5).returncode == 42
        print(f'native record collection: {lookups} lookups for {records} records; cross-package payloads/order {order}: PASS')
