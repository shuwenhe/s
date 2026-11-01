#!/usr/bin/env python3
"""Measure semantic work during annotation without wall-clock thresholds."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
ir = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / '.bootstrap/native-imports/stage1.ir'
seed = root / 'bin/s_seed'
with tempfile.TemporaryDirectory(prefix='s-annotation-cost-') as directory:
    work = Path(directory)
    lines = ir.read_text().splitlines()
    output = []
    pending = False
    inserted = 0
    for line in lines:
        if line == 'FUNC_BEGIN|infer_expr_in_scope|_|_':
            pending = True
        elif pending and not line.startswith('PARAM|'):
            output.extend(['ARG|"annotation-cost: infer"|_|_', 'CALL|__cost_trace|eprintln|1'])
            pending = False
            inserted += 1
        output.append(line)
    assert inserted == 1, 'compiler IR must contain exactly one semantic inference entry'
    traced_ir = work / 'compiler.ir'
    traced_ir.write_text('\n'.join(output) + '\n')
    compiler = work / 'compiler'
    subprocess.run([str(seed), '--emit-standalone-amd64', str(traced_ir), str(compiler)], cwd=root, check=True, timeout=90)
    body = 'return input + 1'
    for _ in range(8):
        body = 'if input > 0 { ' + body + ' }; return input'
    source = work / 'main.s'
    source.write_text('package main\nfunc main(int input) int { ' + body + ' }\n')
    artifact = work / 'main.sasm'
    result = subprocess.run([str(compiler), '--compile-unit', str(artifact), str(source)],
                            env={**os.environ, 'S_CANONICAL_TRACE': '1'}, capture_output=True, text=True, check=True, timeout=60)
    log = result.stderr
    start = log.index('canonical: semantic complete')
    end = log.index('canonical: semantic call annotation complete')
    checking = log[:start].count('annotation-cost: infer')
    annotation = log[start:end].count('annotation-cost: infer')
    assert checking > 0
    assert annotation < checking * 6, f'repeated statement checking: {annotation} annotation calls vs {checking} checking calls'
    binary = work / 'main'
    subprocess.run([str(compiler), '--emit-bin', str(artifact), str(binary)], check=True, timeout=30)
    for argument, wanted in [('7', 8), ('0', 0)]:
        result = subprocess.run([str(binary), argument], timeout=10)
        assert result.returncode == wanted, (argument, wanted, result.returncode)
    print(f'annotation inference work: {annotation} calls vs {checking} initial checking calls; nested execution: PASS')
