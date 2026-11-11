"""Build and execute actual database S sources; no simulated server integration."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


def library_sources():
    return [ROOT / 'src/option/option.s', ROOT / 'src/result/result.s', ROOT / 'src/prelude/prelude.s',
            ROOT / 'src/std/database/types.s', ROOT / 'src/std/database/lifecycle.s',
            ROOT / 'src/std/database/rows.s', ROOT / 'src/std/database/interfaces.s']


class NativeDatabaseCase(unittest.TestCase):
    def execute(self, fixture, extra=(), expected=0):
        compiler = Path(os.environ.get('S_DATABASE_COMPILER', ROOT / 'bin/s_seed')).resolve()
        seed = compiler.name == 's_seed'
        with tempfile.TemporaryDirectory(prefix='s-database-native-') as directory:
            work = Path(directory)
            intermediate, binary = work / 'program.ir', work / 'program'
            sources = [*library_sources(), *extra, ROOT / 'test/stdlib-native' / fixture]
            for source in sources:
                self.assertTrue(source.is_file(), f'missing implementation: {source}')
            commands = [
                [str(compiler), '--compile-native-unit' if seed else '--compile-unit',
                 str(intermediate), *map(str, sources)],
                [str(compiler), '--emit-standalone-amd64' if seed else '--emit-bin',
                 str(intermediate), str(binary)],
            ]
            for command in commands:
                completed = subprocess.run(command, cwd=ROOT, capture_output=True,
                                           env=os.environ | {'S_SOURCE_ROOT': str(ROOT)}, timeout=90)
                self.assertEqual(completed.returncode, 0, completed.stderr.decode(errors='replace'))
            completed = subprocess.run([str(binary)], capture_output=True, timeout=20)
            self.assertEqual(completed.returncode, expected,
                             f'exit {completed.returncode}: {completed.stdout!r} {completed.stderr!r}')
            return completed
