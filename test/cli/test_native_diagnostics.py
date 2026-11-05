"""A diagnostic command that detects an error must fail and retain output."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
COMPILER = Path(os.environ.get('S_TEST_COMPILER', ROOT / 'bin/s_compiler')).resolve()


class DiagnosticStatusTests(unittest.TestCase):
    def test_reported_mir_error_is_failure_and_preserves_previous_output(self):
        with tempfile.TemporaryDirectory() as directory:
            source, output = Path(directory) / 'main.s', Path(directory) / 'output.mir'
            source.write_text('package main\nfunc main() int { return missing_name }\n')
            sentinel = b'previous valid output\n'
            for mode in ('--emit-mir', '--emit-mir-after-drop'):
                with self.subTest(mode=mode):
                    output.write_bytes(sentinel)
                    result = subprocess.run([str(COMPILER), mode, str(source), str(output)],
                                            capture_output=True, timeout=30)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(b'mir-error', result.stderr)
                    self.assertEqual(output.read_bytes(), sentinel)


if __name__ == '__main__':
    unittest.main()
