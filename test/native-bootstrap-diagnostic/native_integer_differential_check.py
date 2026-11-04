#!/usr/bin/env python3
"""Compare native integer operations with an independent fixed-width oracle."""
from pathlib import Path
import argparse
import json
import os
import random
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PARSER = argparse.ArgumentParser(description=__doc__)
PARSER.add_argument('compiler', nargs='?', type=Path)
PARSER.add_argument('--seed', action='store_true', help='exercise the seed standalone backend directly')
ARGS = PARSER.parse_args()
COMPILER = ARGS.compiler.resolve() if ARGS.compiler else ROOT / ('bin/s_seed' if ARGS.seed else 'bin/s_compiler')
MASK = (1 << 64) - 1
MIN = -(1 << 63)
MAX = (1 << 63) - 1


def signed(value):
    value &= MASK
    return value - (1 << 64) if value > MAX else value


def quotient(left, right):
    value = abs(left) // abs(right)
    return -value if (left < 0) != (right < 0) else value


def literal(value):
    return '(-9223372036854775807 - 1)' if value == MIN else f'({value})'


def main():
    rng = random.Random(20261104)
    operands = [MIN, MIN + 1, -65, -1, 0, 1, 63, MAX - 1, MAX]
    operands += [-(1 << 62) - 1, -(1 << 62), -(1 << 62) + 1, (1 << 62) - 1, 1 << 62, (1 << 62) + 1]
    operands += [rng.randrange(MIN, MAX + 1) for _ in range(15)]
    divisors = [-1, 1, -3, 7, MIN, MAX]
    with tempfile.TemporaryDirectory(prefix='s-integer-differential-') as directory:
        work = Path(directory)
        functions = []
        rows = []
        for op in ('+', '-', '*', '/', '%'):
            for constant in divisors:
                index = len(rows)
                functions.append(f'func case{index}(int value) int {{ return value {op} {literal(constant)} }}')
                rows.append((op, constant))
        body = []
        checks = []
        for index, (op, constant) in enumerate(rows):
            assertions = []
            for operand_index, operand in enumerate(operands):
                if op == '+': expected = signed(operand + constant)
                elif op == '-': expected = signed(operand - constant)
                elif op == '*': expected = signed(operand * constant)
                elif op == '/': expected = signed(quotient(operand, constant))
                else: expected = signed(operand - quotient(operand, constant) * constant)
                assertions.append(f'if case{index}({literal(operand)}) != {literal(expected)} {{ return {operand_index + 1} }}')
            body.extend(assertions)
            checks.append(f'func check{index}() int {{\n' + '\n'.join(assertions) + '\nreturn 0\n}')
        source = work / 'main.s'
        if ARGS.seed:
            entry = '\nfunc main() int {\n' + '\n'.join(f'if check{i}() != 0 {{ return {i + 1} }}' for i in range(len(checks))) + '\nreturn 0\n}\n'
        else:
            entry = '\nfunc main(int selector) int {\n' + '\n'.join(f'if selector == {i} {{ return check{i}() }}' for i in range(len(checks))) + '\nreturn 255\n}\n'
        source.write_text('package main\n' + '\n'.join(functions + checks) + entry)
        assembly, binary = work / 'main.sasm', work / 'main'
        subprocess.run([str(COMPILER), '--compile-unit', str(assembly), str(source)], check=True, timeout=120)
        subprocess.run([str(COMPILER), '--emit-standalone-amd64' if ARGS.seed else '--emit-bin', str(assembly), str(binary)], check=True, timeout=60, env=dict(os.environ, S_SOURCE_ROOT=str(ROOT)))
        if ARGS.seed:
            result = subprocess.run([str(binary)], timeout=15, capture_output=True)
            assert result.returncode == 0, ('seed standalone', 'case', result.returncode, result.stderr)
            print(json.dumps({'seed': 20261104, 'cases': len(body), 'backend': 'seed standalone'}))
            print('seed standalone integer differential: PASS')
            return
        for index, (op, constant) in enumerate(rows):
            result = subprocess.run([str(binary), str(index)], timeout=15, capture_output=True)
            assert result.returncode == 0, (op, constant, 'operand', operands[result.returncode - 1] if 1 <= result.returncode <= len(operands) else result.returncode, result.stderr)
        print(json.dumps({'seed': 20261104, 'cases': len(body), 'operations': ['+', '-', '*', '/', '%']}))
    print('native integer differential: signed wraparound, truncated division and remainder: PASS')


if __name__ == '__main__':
    main()
