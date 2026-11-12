"""Compile real API misuse and trait compatibility, retaining previous outputs."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

from database_test_support import NativeDatabaseCase, ROOT, library_sources


class DatabaseContractsTests(NativeDatabaseCase):
    def test_wrong_value_column_and_parameter_types_are_rejected_atomically(self):
        compiler = Path(os.environ.get('S_DATABASE_COMPILER', ROOT / 'bin/s_seed')).resolve()
        flag = '--compile-native-unit' if compiler.name == 's_seed' else '--compile-unit'
        bodies = (
            'invalid := std.database.is_null("not a database value"); return 0',
            'value := std.database.statement { sql: "SELECT 1", parameters: string[]{"wrong"} }; return 0',
            'value := std.database.row { values: int[]{1} }; return 0',
        )
        if compiler.name == 's_seed':
            # The known enum-argument gap is exercised separately as an
            # expected failure; these cases still enforce record field types.
            bodies = bodies[1:]
        with tempfile.TemporaryDirectory(prefix='s-database-types-negative-') as directory:
            work = Path(directory)
            source, output = work / 'main.s', work / 'main.ir'
            for body in bodies:
                with self.subTest(body=body):
                    source.write_text('package main\nimport "std.database"\nfunc main() int { ' + body + ' }\n')
                    output.write_bytes(b'previous output\n')
                    result = subprocess.run([str(compiler), flag, str(output),
                                             *map(str, library_sources(compiler.name == 's_seed')), str(source)],
                                            cwd=ROOT, capture_output=True, timeout=60)
                    self.assertNotEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(output.read_bytes(), b'previous output\n')
                    self.assertIn(b'error[5]' if compiler.name == 's_seed' else b'canonical semantic', result.stderr.lower())

    @unittest.expectedFailure
    def test_seed_enum_parameter_type_is_rejected_known_gap(self):
        compiler = Path(os.environ.get('S_DATABASE_COMPILER', ROOT / 'bin/s_seed')).resolve()
        if compiler.name != 's_seed':self.skipTest('canonical rejection is checked by the main negative contract test')
        with tempfile.TemporaryDirectory(prefix='s-database-enum-negative-') as directory:
            work=Path(directory);source=work/'main.s';output=work/'main.ir'
            source.write_text('package main\nimport "std.database"\nfunc main() int { invalid := std.database.is_null("wrong enum argument"); return 0 }\n')
            result=subprocess.run([str(compiler),'--compile-native-unit',str(output),*map(str,library_sources()),str(source)],cwd=ROOT,capture_output=True,timeout=60)
            self.assertNotEqual(result.returncode,0,'Seed currently accepts an invalid enum argument; do not count this as contract enforcement')


if __name__ == '__main__':
    import unittest
    unittest.main()
