"""Persistent collections execute with the real public compiler."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class NativeCollectionsTests(unittest.TestCase):
    def test_wrong_generic_values_and_keys_preserve_previous_outputs(self):
        with tempfile.TemporaryDirectory(prefix='s-collections-negative-') as directory:
            work = Path(directory)
            source, output = work / 'main.s', work / 'main.sasm'
            for body in ('values,error := std.collections.new_vector(int[]{1}); changed,failure := std.collections.vector_push(values,"wrong"); return 0',
                         'values,error := std.collections.new_map(string[]{"a"},int[]{1}); changed,failure := std.collections.map_put(values,42,2); return 0'):
                source.write_text('package main\nimport "std.collections"\nfunc main() int { ' + body + ' }\n')
                for seed in (False,True):
                    with self.subTest(seed=seed,body=body):
                        output.write_bytes(b'previous output\n')
                        compiler = ROOT / 'bin' / ('s_seed' if seed else 's_compiler')
                        command = [str(compiler), '--compile-native-unit' if seed else '--compile-unit', str(output), str(source),
                                   str(ROOT / 'src/std/collections.s'),str(ROOT / 'src/option/option.s'),
                                   str(ROOT / 'src/result/result.s'),str(ROOT / 'src/prelude/prelude.s')]
                        result = subprocess.run(command,cwd=ROOT,capture_output=True,timeout=60)
                        self.assertNotEqual(result.returncode,0)
                        self.assertEqual(output.read_bytes(),b'previous output\n')

    def test_native_and_seed_collection_contracts(self):
        for seed in (False, True):
            with self.subTest(seed=seed), tempfile.TemporaryDirectory(prefix='s-collections-') as directory:
                work = Path(directory)
                binary = work / 'collections'
                entry = work / 'main.s'
                entry.write_bytes((ROOT / 'test/stdlib-native/collections.s').read_bytes())
                if seed:
                    intermediate = work / 'main.ir'
                    commands = [[str(ROOT / 'bin/s_seed'), '--compile-native-unit', str(intermediate), str(entry),
                                 str(ROOT / 'src/std/collections.s'), str(ROOT / 'src/option/option.s'),
                                 str(ROOT / 'src/result/result.s'), str(ROOT / 'src/prelude/prelude.s'), str(ROOT / 'src/std/time.s')],
                                [str(ROOT / 'bin/s_seed'), '--emit-standalone-amd64', str(intermediate), str(binary)]]
                else:
                    commands = [['sh', str(ROOT / 'misc/scripts/s-driver.sh'), 'build', str(entry), '-o', str(binary)]]
                for command in commands:
                    result = subprocess.run(command, cwd=ROOT, env=os.environ | {'S_SOURCE_ROOT': str(ROOT)},
                                            capture_output=True, timeout=90)
                    self.assertEqual(result.returncode, 0, result.stderr)
                result = subprocess.run([str(binary)], capture_output=True, timeout=20)
                self.assertEqual(result.returncode, 0, (result.stdout, result.stderr))
                self.assertIn(b'collections: PASS', result.stdout)
                benchmark = subprocess.run([str(binary), '--benchmark-seed' if seed else '--benchmark'],
                                           capture_output=True,timeout=20)
                self.assertEqual(benchmark.returncode,0,(benchmark.stdout,benchmark.stderr))
                print(('seed ' if seed else 'native ') + benchmark.stdout.decode().strip())


if __name__ == '__main__':
    unittest.main()
