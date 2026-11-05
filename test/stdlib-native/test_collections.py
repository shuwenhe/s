"""Persistent collections execute with the real public compiler."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class NativeCollectionsTests(unittest.TestCase):
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
                                 str(ROOT / 'src/result/result.s'), str(ROOT / 'src/prelude/prelude.s')],
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


if __name__ == '__main__':
    unittest.main()
