"""Imported mutable APIs retain nominal owners from transparent tuple bindings."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SeedImportedBorrowTests(unittest.TestCase):
    def test_qualified_source_functions_override_legacy_runtime_leaf_aliases(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            api = work / 'api.s'
            api.write_text('package api\nstruct Value { int number }\n'
                           'func slice(string text, int start, int end) Value { return Value { number: 40 } }\n'
                           'func byte_at(string text, int index) int { return 2 }\n')
            source = work / 'main.s'
            source.write_text('package main\nimport "api"\nfunc main() int { '
                              'value := api.slice("x",0,1); return value.number + api.byte_at("x",0) }\n')
            intermediate, binary = work / 'main.ir', work / 'program'
            for command in ([str(ROOT / 'bin/s_seed'), '--compile-native-unit', str(intermediate), str(api), str(source)],
                            [str(ROOT / 'bin/s_seed'), '--emit-standalone-amd64', str(intermediate), str(binary)]):
                result = subprocess.run(command, cwd=ROOT, env=os.environ | {'S_SOURCE_ROOT': str(ROOT)},
                                        capture_output=True, timeout=60)
                self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(binary)], capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 42, result.stderr)

    def test_imported_tuple_owner_and_rejected_wrong_or_expired_owner(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            api = work / 'api.s'
            api.write_text('''package api
struct Value { int number }
func create_value() (Value,int) { return Value { number: 1 }, 0 }
func reset(Value* value) int { value.number = 42; return 0 }
''')
            for name, body, wanted in (
                ('valid', 'value, error := api.create_value(); api.reset(value*); return value.number', 42),
                ('wrong', 'value := Other { number: 1 }; api.reset(value*); return 0', None),
                ('scope', '{ value, error := api.create_value() }; api.reset(value*); return 0', None),
            ):
                with self.subTest(name=name):
                    source = work / 'main.s'
                    source.write_text('package main\nimport "api"\nstruct Other { int number }\nfunc main() int { ' + body + ' }\n')
                    intermediate, binary = work / (name + '.ir'), work / name
                    intermediate.write_bytes(b'previous output\n')
                    result = subprocess.run([str(ROOT / 'bin/s_seed'), '--compile-native-unit', str(intermediate),
                                             str(ROOT / 'src/result/result.s'), str(api), str(source)],
                                            capture_output=True, timeout=60)
                    if wanted is None:
                        self.assertNotEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(intermediate.read_bytes(), b'previous output\n')
                        continue
                    self.assertEqual(result.returncode, 0, result.stderr)
                    result = subprocess.run([str(ROOT / 'bin/s_seed'), '--emit-standalone-amd64',
                                             str(intermediate), str(binary)], cwd=ROOT,
                                            env=os.environ | {'S_SOURCE_ROOT': str(ROOT)}, capture_output=True, timeout=60)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    result = subprocess.run([str(binary)], capture_output=True, timeout=10)
                    self.assertEqual(result.returncode, wanted, result.stderr)


if __name__ == '__main__':
    unittest.main()
