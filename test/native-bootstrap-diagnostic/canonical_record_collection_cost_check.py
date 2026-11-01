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
    source = 'package main\n'
    source += ''.join(f'struct Record{i} {{ int value }}\n' for i in range(size))
    source += ''.join(f'func helper{i}(int value) int {{ return value + 1 }}\n' for i in range(size))
    source += 'func main() int { return 42 }\n'
    (work / 'main.s').write_text(source)
    artifact = work / 'main.sasm'
    result = subprocess.run([str(compiler), '--compile-unit', str(artifact), str(work / 'main.s')], cwd=root, capture_output=True, text=True, check=True, timeout=60)
    scope = result.stderr.split('record-cost: begin\n', 1)[1].split('record-cost: end\n', 1)[0]
    lookups = scope.count('record-cost: package')
    assert lookups <= size * 3, f'repeated AST rescans: {lookups} package lookups for {size} records'
    binary = work / 'main'
    subprocess.run([str(compiler), '--emit-bin', str(artifact), str(binary)], check=True, timeout=30)
    assert subprocess.run([str(binary)], timeout=5).returncode == 42
    print(f'native record collection: {lookups} package lookups for {size} records; execution: PASS')
