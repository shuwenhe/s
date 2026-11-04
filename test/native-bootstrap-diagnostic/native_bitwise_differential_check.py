#!/usr/bin/env python3
"""Independent signed-64 oracle for established binary bit operations."""
import argparse
import os
from pathlib import Path
import random
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MASK = (1 << 64) - 1
MIN, MAX = -(1 << 63), (1 << 63) - 1


def signed(value):
    value &= MASK
    return value - (1 << 64) if value > MAX else value


def oracle(op, left, right):
    if op == '&': return signed(left & right)
    if op == '|': return signed(left | right)
    if op == '^': return signed(left ^ right)
    if op == '<<': return signed(left << (right & 63))
    return left >> (right & 63)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, default=ROOT / 'bin/s_compiler')
    parser.add_argument('--seed', action='store_true')
    parser.add_argument('--small', action='store_true', help='historical seed carrier-safe operands/results')
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    rng = random.Random(20261104)
    values = [MIN, MIN + 1, -(1 << 62), -65, -1, 0, 1, 63, 255,
              0x5555555555555555, signed(0xaaaaaaaaaaaaaaaa), MAX]
    values += [rng.randrange(MIN, MAX + 1) for _ in range(3)]
    counts = [-129, -65, -64, -63, -1, 0, 1, 7, 31, 32, 62, 63, 64, 65, 127, MAX, MIN]
    if args.small:
        values = [-1000, -8, -1, 0, 1, 63, 1024]
        counts = [-64, 0, 1, 7, 64, 65]
    functions, calls, cases = [], [], 0
    for index, op in enumerate(('&', '|', '^', '<<', '>>')):
        functions.append(f'func operation{index}(int left, int right) int {{ return left {op} right }}')
        rows = [(left, right) for left in values for right in (counts if index >= 3 else values)]
        for begin in range(0, len(rows), 40):
            name = f'check{len(calls)}'
            assertions = [f'if operation{index}({left}, {right}) != {oracle(op, left, right)} {{ return {i + 1} }}'
                          for i, (left, right) in enumerate(rows[begin:begin + 40])]
            functions.append(f'func {name}() int {{\n' + '\n'.join(assertions) + '\nreturn 0\n}')
            calls.append(f'if {name}() != 0 {{ return {len(calls) + 1} }}')
        cases += len(rows)
    functions.append('''func integration(int first, int second, int count, int fourth) int {
    shifted := first << count
    total := 0
    i := 0
    for i < 4 { total = total | (second << i); i = i + 1 }
    return shifted + total + fourth
}
func precedence() int {
    value := 7
    value &= 3
    value |= 8
    value ^= 1
    if value != 10 { return 1 }
    if (1 | 2 ^ 3 & 7) != 1 || (1 << 2 + 1) != 8 { return 2 }
    if (64 >> 1 >> 2) != 8 || (8 >> 1 + 1) != 2 { return 3 }
    if integration(1, 1, 3, 19) != 42 { return 4 }
    return 0
}''')
    calls.append('if precedence() != 0 { return 200 }')
    functions.append('func main() int {\n' + '\n'.join(calls) + '\nreturn 42\n}')
    with tempfile.TemporaryDirectory(prefix='s-bitwise-oracle-') as directory:
        work = Path(directory)
        source, assembly, binary = work / 'main.s', work / 'main.sasm', work / 'main'
        program = 'package main\n' + '\n'.join(functions)
        if args.seed:
            # Historical seed syntax has no bitwise compound assignments.
            # Keep the same operations and assertions using explicit updates.
            program = program.replace('value &= 3', 'value = value & 3').replace('value |= 8', 'value = value | 8').replace('value ^= 1', 'value = value ^ 1')
        source.write_text(program)
        result = subprocess.run([str(compiler), '--compile-native-unit' if args.seed else '--compile-unit', str(assembly), str(source)], capture_output=True, timeout=120)
        assert result.returncode == 0, result.stderr.decode()
        subprocess.run([str(compiler), '--emit-standalone-amd64' if args.seed else '--emit-bin', str(assembly), str(binary)],
                       check=True, timeout=60, env=dict(os.environ, S_SOURCE_ROOT=str(ROOT)))
        result = subprocess.run([str(binary)], capture_output=True, timeout=15)
        assert result.returncode == 42, (result.returncode, result.stderr)
        for op in ('&', '|', '^', '<<', '>>'):
            for expr in (f'true {op} false', f'"a" {op} "b"', f'1 {op} true'):
                source.write_text('package main\nfunc main() int { return ' + expr + ' }\n')
                assembly.write_bytes(b'preserve artifact\n')
                result = subprocess.run([str(compiler), '--compile-native-unit' if args.seed else '--compile-unit', str(assembly), str(source)], capture_output=True, timeout=30)
                assert result.returncode != 0, ('accepted invalid operand', expr)
                assert assembly.read_bytes() == b'preserve artifact\n', ('clobbered output', expr)
    print(f'bitwise differential: {cases} oracle cases, precedence/compound/phi/RCX integration and 15 negatives: PASS')


if __name__ == '__main__':
    main()
