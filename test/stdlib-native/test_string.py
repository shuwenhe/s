"""Byte strings and strict conversions through actual S native and seed compilers."""
from pathlib import Path
import os
import random
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class NativeStringTests(unittest.TestCase):
    def compile_run(self, source, seed=False):
        with tempfile.TemporaryDirectory(prefix='s-string-') as directory:
            work = Path(directory)
            entry = work / 'main.s'
            entry.write_text(source)
            binary = work / 'program'
            if seed:
                intermediate = work / 'seed.ir'
                sources = [entry, ROOT / 'src/std/string.s', ROOT / 'src/std/time.s',
                           ROOT / 'src/result/result.s', ROOT / 'src/prelude/prelude.s']
                commands = [[str(ROOT / 'bin/s_seed'), '--compile-native-unit', str(intermediate), *map(str, sources)],
                            [str(ROOT / 'bin/s_seed'), '--emit-standalone-amd64', str(intermediate), str(binary)]]
            else:
                commands = [['sh', str(ROOT / 'misc/scripts/s-driver.sh'), 'build', str(entry), '-o', str(binary)]]
            for command in commands:
                result = subprocess.run(command, cwd=ROOT, env=os.environ | {'S_SOURCE_ROOT': str(ROOT)}, capture_output=True, timeout=90)
                self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(binary)], capture_output=True, timeout=15)
            self.assertEqual(result.returncode, 0, (result.stdout, result.stderr))
            return result.stdout

    def test_api_boundaries_and_repetitive_search_native_and_seed(self):
        for seed in (False, True):
            with self.subTest(seed=seed):
                output = self.compile_run((ROOT / 'test/stdlib-native/string.s').read_text(), seed)
                self.assertIn(b'string: PASS', output)
                print(('seed ' if seed else 'native ') + output.decode().strip())

    def test_intrinsic_wrong_array_type_is_rejected_without_replacing_output(self):
        with tempfile.TemporaryDirectory(prefix='s-string-types-') as directory:
            work = Path(directory)
            source = work / 'main.s'
            source.write_text('package main\nextern "intrinsic" func __std_string_array_concat(int[] a, int[] b) int[]\n'
                              'func main() int { values := __std_string_array_concat(int[]{1},int[]{2}); return len(values) }\n')
            intermediate = work / 'main.sasm'
            intermediate.write_bytes(b'previous output\n')
            result = subprocess.run([str(ROOT / 'bin/s_compiler'), '--compile-unit', str(intermediate), str(source)],
                                    capture_output=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(intermediate.read_bytes(), b'previous output\n')
            seed_ir, binary = work / 'seed.ir', work / 'seed-program'
            result = subprocess.run([str(ROOT / 'bin/s_seed'), '--compile-native-unit', str(seed_ir), str(source)],
                                    capture_output=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            binary.write_bytes(b'previous executable\n')
            result = subprocess.run([str(ROOT / 'bin/s_seed'), '--emit-standalone-amd64', str(seed_ir), str(binary)],
                                    cwd=ROOT, capture_output=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(binary.read_bytes(), b'previous executable\n')

    def test_deterministic_search_split_replace_against_python(self):
        rng = random.Random(20261105)
        functions = []
        calls = []
        for index in range(100):
            text = ''.join(rng.choice('abc') for _ in range(rng.randrange(30)))
            needle = ''.join(rng.choice('abc') for _ in range(rng.randrange(1, 6)))
            body = []
            body.append(f'if std.string.index_of("{text}", "{needle}") != {text.find(needle)} {{ return 31 }}')
            body.append(f'fields{index}, error{index} := std.string.split("{text}", "{needle}")\nif error{index}.code != 0 || std.string.join(fields{index}, "{needle}") != "{text}" {{ return 32 }}')
            body.append(f'replaced{index}, failure{index} := std.string.replace("{text}", "{needle}", "X")\nif failure{index}.code != 0 || replaced{index} != "{text.replace(needle, "X")}" {{ return 33 }}')
            functions.append(f'func case{index}() int {{\n' + '\n'.join(body) + '\nreturn 0\n}\n')
            calls.append(f'if case{index}() != 0 {{ return 34 }}')
        source = 'package main\nimport "std.string"\n' + '\n'.join(functions) + '\nfunc main() int {\n' + '\n'.join(calls) + '\nreturn 0\n}\n'
        self.compile_run(source)


if __name__ == '__main__':
    unittest.main()
