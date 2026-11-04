#!/usr/bin/env python3
"""Retain reproducible canonical-native/C measurements in a new directory."""
import argparse
import hashlib
import json
import platform
from pathlib import Path
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
WORKLOADS = {
    'sum': (20000000, '''package main
func main(int n) int {
    total := 0
    for i := 0; i < n; i = i + 1 { total = total + i }
    if total == n * (n - 1) / 2 { return 42 }
    return 1
}
''', '''#include <stdint.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    int64_t n = strtoll(argv[1], 0, 10), total = 0;
    for (int64_t i = 0; i < n; ++i) total += i;
    return total == n * (n - 1) / 2 ? 42 : 1;
}
'''),
    'fibonacci': (32, '''package main
func fib(int n) int {
    if n < 2 { return n }
    return fib(n - 1) + fib(n - 2)
}
func main(int n) int {
    if fib(n) == 2178309 { return 42 }
    return 1
}
''', '''#include <stdint.h>
#include <stdlib.h>
static int64_t fib(int64_t n) {
    if (n < 2) return n;
    return fib(n - 1) + fib(n - 2);
}
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    return fib(strtoll(argv[1], 0, 10)) == 2178309 ? 42 : 1;
}
'''),
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def capture(*command):
    return subprocess.check_output(command, cwd=ROOT, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path, help='new retained evidence directory')
    parser.add_argument('--compiler', type=Path, default=ROOT / 'bin/s_compiler')
    parser.add_argument('--cc', default='cc')
    parser.add_argument('--runs', type=int, default=5)
    args = parser.parse_args()
    if args.runs < 3:
        parser.error('at least three measured runs required')
    compiler = args.compiler.resolve(strict=True)
    args.output.mkdir(parents=True, exist_ok=False)
    output = args.output.resolve()
    report = {
        'revision': capture('git', 'rev-parse', 'HEAD'),
        'dirty_status': capture('git', 'status', '--porcelain'),
        'compiler': str(compiler), 'compiler_sha256': digest(compiler),
        'host': platform.uname()._asdict(),
        'cc_version': capture(args.cc, '--version'),
        'time_version': capture('/usr/bin/time', '--version'),
        'notes': ['Canonical native source-to-MIR path; no legacy C lowering.',
                  'C uses -O2; optimizer differences are included in the measurement.',
                  'Tiny process timings include startup and may fall below timer resolution.',
                  'No CPU isolation; concurrent load can affect measurements.'],
        'measurements': [],
    }
    (output / 'benchmark-native.py').write_bytes(Path(__file__).read_bytes())
    if Path('/proc/cpuinfo').exists():
        (output / 'cpuinfo.txt').write_bytes(Path('/proc/cpuinfo').read_bytes())
    (output / 'source.diff').write_text(capture('git', 'diff', 'HEAD'))

    def measure(label, command, expected=0):
        usage = output / (label + '.usage')
        start = time.perf_counter()
        with (output / (label + '.stdout')).open('wb') as stdout, (output / (label + '.stderr')).open('wb') as stderr:
            result = subprocess.run(['/usr/bin/time', '-f', '%M', '-o', str(usage), '--', *map(str, command)],
                                    stdout=stdout, stderr=stderr, timeout=120)
        entry = {'label': label, 'command': list(map(str, command)),
                 'elapsed_seconds': time.perf_counter() - start,
                 'peak_rss_kib': int(usage.read_text().splitlines()[-1]),
                 'returncode': result.returncode}
        report['measurements'].append(entry)
        (output / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
        if result.returncode != expected:
            raise RuntimeError(f'{label}: expected exit {expected}, got {result.returncode}; see retained logs')
        return entry

    for name, (argument, s_source, c_source) in WORKLOADS.items():
        source = output / (name + '.s')
        reference = output / (name + '.c')
        assembly = output / (name + '.sasm')
        source.write_text(s_source)
        reference.write_text(c_source)
        measure(name + '-s-compile', [compiler, '--compile-unit', assembly, source])
        measure(name + '-s-link', [compiler, '--emit-bin', assembly, output / (name + '-s')])
        measure(name + '-c-build', [args.cc, '-O2', '-o', output / (name + '-c'), reference])
        for language in ('s', 'c'):
            command = [output / (name + '-' + language), argument]
            measure(name + '-' + language + '-warmup', command, 42)
            samples = [measure(f'{name}-{language}-run-{i}', command, 42)['elapsed_seconds'] for i in range(args.runs)]
            print(f'{name} {language}: median={statistics.median(samples):.6f}s ({args.runs} runs)')
    if digest(compiler) != report['compiler_sha256']:
        raise RuntimeError('compiler changed during benchmark')
    report['artifact_sha256'] = {p.name: digest(p) for p in output.iterdir() if p.suffix in ('.s', '.c', '.sasm') or p.name.endswith(('-s', '-c'))}
    report['complete'] = True
    (output / 'results.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
