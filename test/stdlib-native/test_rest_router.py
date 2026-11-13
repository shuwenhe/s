"""Execute identical routing contract using native and Seed standalone binaries."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[2]
class RouterTests(unittest.TestCase):
    def test_router_both_compilers(self):
        with tempfile.TemporaryDirectory(prefix='s-rest-router-') as work:
            for seed in (False, True):
                with self.subTest(seed=seed):
                    producer = ROOT / 'bin/s_seed' if seed else Path(os.environ.get('S_TEST_COMPILER', ROOT / 'bin/s_compiler'))
                    unit = Path(work) / ('seed.ir' if seed else 'native.sasm')
                    binary = Path(work) / ('seed' if seed else 'native')
                    commands = [
                        [str(producer), '--compile-native-unit' if seed else '--compile-unit', str(unit), str(ROOT/'src/std/rest/router.s'), str(ROOT/'src/result/result.s'), str(ROOT/'src/option/option.s'), str(ROOT/'src/prelude/prelude.s'), str(ROOT/'test/rest/router.s')],
                        [str(producer), '--emit-standalone-amd64' if seed else '--emit-bin', str(unit), str(binary)],
                        [str(binary)],
                    ]
                    for command in commands:
                        result = subprocess.run(command, cwd=ROOT, env=os.environ | {'S_SOURCE_ROOT':str(ROOT)}, capture_output=True, timeout=90)
                        self.assertEqual(result.returncode, 0, f'{command}: {result.stdout!r} {result.stderr!r}')
                    self.assertEqual(result.stdout, b'rest router: PASS\n')
if __name__ == '__main__': unittest.main()
