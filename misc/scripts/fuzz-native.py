#!/usr/bin/env python3
"""Deterministic compiler-input mutations with retained crash/timeout evidence.

This is bounded fuzz coverage, not a proof of safety for every program.
"""
import argparse
import hashlib
import json
from pathlib import Path
import random
import resource
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
BASES = (
    'package main\nfunc main() int { return 42 }\n',
    'package main\nfunc main(int n) int { if n > 0 { return n }; return 0 }\n',
    'package main\nfunc main() int { values := int[]{1, 2}; return values[0] }\n',
    'package main\nstruct item { int value }\nfunc main() int { x := item { value: 42 }; return x.value }\n',
    'package main\nfunc id[T](T value) T { return value }\nfunc main() int { return id(42) }\n',
)
NEGATIVES = (
    'package main\nfunc main() int { return missing_name }\n',
    'package main\nfunc main() int { return true }\n',
    'package main\nfunc main() int { return 9223372036854775808 }\n',
    'package main\nfunc main() int { return "unterminated }\n',
    'package main\nfunc main() int { return 42\n',
)


def limits():
    resource.setrlimit(resource.RLIMIT_AS, (256 * 1024**2,) * 2)
    resource.setrlimit(resource.RLIMIT_CPU, (3, 3))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path, help='new retained corpus/report directory')
    parser.add_argument('--compiler', type=Path, default=ROOT / 'bin/s_compiler')
    parser.add_argument('--cases', type=int, default=1024)
    parser.add_argument('--seed', type=int, default=20261105)
    args = parser.parse_args()
    if args.cases < len(NEGATIVES):
        parser.error('case count must cover all required negatives')
    args.output.mkdir(parents=True, exist_ok=False)
    compiler = args.compiler.resolve(strict=True)
    rng = random.Random(args.seed)
    alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789 {}[]()<>;:+-*/&|!="\'\\\n\t\x00'
    report = {'compiler': str(compiler), 'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
              'seed': args.seed, 'requested_cases': args.cases, 'results': [], 'complete': False}
    failure = None
    for i in range(args.cases):
        source = NEGATIVES[i] if i < len(NEGATIVES) else rng.choice(BASES)
        if i >= len(NEGATIVES):
            for _ in range(rng.randrange(1, 6)):
                at = rng.randrange(len(source) + 1)
                action = rng.randrange(3)
                if action == 0:
                    source = source[:at] + rng.choice(alphabet) + source[at:]
                elif action == 1:
                    source = source[:at] + source[at + 1:]
                else:
                    source = source[:at] + rng.choice(alphabet) + source[at + 1:]
        path = args.output / f'{i:05}.s'
        path.write_bytes(source.encode())
        output = args.output / f'{i:05}.mir'
        sentinel = b'previous output must survive failed compilation\n'
        output.write_bytes(sentinel)
        command = [str(compiler), '--compile-unit', str(output.resolve()), str(path.resolve())]
        started = time.monotonic()
        try:
            result = subprocess.run(command, capture_output=True, timeout=5, preexec_fn=limits)
            (args.output / f'{i:05}.stderr').write_bytes(result.stderr)
            entry = {'case': i, 'exit': result.returncode, 'seconds': time.monotonic() - started,
                     'input_sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
            if result.returncode not in (0, 1, 2):
                failure = f'compiler crash or resource failure at case {i}: exit {result.returncode}'
            elif result.returncode and (not result.stderr or output.read_bytes() != sentinel):
                failure = f'failed compilation lacks diagnostics or changed output at case {i}'
            elif i < len(NEGATIVES) and result.returncode == 0:
                failure = f'known invalid program accepted at case {i}'
            if path.read_bytes() != source.encode():
                failure = f'compiler changed source at case {i}'
        except subprocess.TimeoutExpired:
            entry = {'case': i, 'exit': 'TIMEOUT', 'seconds': time.monotonic() - started}
            failure = f'compiler timeout at case {i}'
        report['results'].append(entry)
        if failure:
            report['failure'] = failure
            break
    report['complete'] = failure is None and len(report['results']) == args.cases
    (args.output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    if failure:
        raise SystemExit(failure + '; retained at ' + str(args.output))
    print(json.dumps({'seed': args.seed, 'cases': args.cases, 'status': 'PASS'}))


if __name__ == '__main__':
    main()
