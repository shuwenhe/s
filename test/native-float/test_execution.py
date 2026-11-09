"""Execute canonical floating-point, array and byte-index regression programs."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
COMPILER = Path(os.environ.get('S_NATIVE_COMPILER', ROOT / 'bin/s_compiler'))


class NativeFloat(unittest.TestCase):
    def test_real_native_programs(self):
        fixtures = [
            ('test/native-float/arithmetic.s', 0),
            ('test/native-float/storage.s', 0),
            ('test/native-float/coercion.s', 0),
            ('test/fixtures/neurx-frontend/string_index.s', 0),
            ('test/fixtures/neurx-frontend/negative_zero.s', 0),
            ('test/fixtures/neurx-frontend/make_array.s', 0),
            ('test/fixtures/neurx-frontend/make_nominal.s', 0),
            ('test/fixtures/neurx-frontend/float_arrays.s', 4),
        ]
        with tempfile.TemporaryDirectory() as temporary:
            for filename, expected in fixtures:
                with self.subTest(source=filename):
                    output = Path(temporary) / Path(filename).stem
                    result = subprocess.run([str(COMPILER), 'build', str(ROOT / filename), str(output)], capture_output=True, text=True, timeout=90)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    result = subprocess.run([str(output)], capture_output=True, text=True, timeout=10)
                    self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
