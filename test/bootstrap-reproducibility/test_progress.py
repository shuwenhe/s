"""Exercise progress reporting against the real seed compiler."""
from pathlib import Path
import os
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SeedProgressTests(unittest.TestCase):
    def compile(self, source, enabled='1'):
        with tempfile.TemporaryDirectory(prefix='s-progress-') as directory:
            work = Path(directory)
            (work / 'main.s').write_text(source)
            return subprocess.run(
                [str(ROOT / 'bin/s_seed'), '--compile-native-unit',
                 str(work / 'main.ir'), str(work / 'main.s')],
                env=os.environ | {'S_BOOTSTRAP_PROGRESS': enabled},
                capture_output=True, text=True, timeout=30)

    def test_counts_and_current_function(self):
        result = self.compile('package main\nfunc helper() int { return 1 }\n'
                              'func main() int { return helper() }\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('PARSING  1 / 1 files  current=done', result.stderr)
        self.assertIn('BORROW CHECK  2 / 2 functions  current=done', result.stderr)
        self.assertIn('current=helper', result.stderr)
        self.assertIn('current=main', result.stderr)
        self.assertRegex(result.stderr, r'SEMANTIC ANALYSIS  (\d+) / \1 items  current=done')

    def test_failure_identifies_function_without_completion(self):
        result = self.compile('package main\nfunc broken() int { return unknown_name }\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('current=broken', result.stderr)
        self.assertIsNone(re.search(r'SEMANTIC ANALYSIS.*current=done', result.stderr))

    def test_progress_can_be_disabled(self):
        result = self.compile('package main\nfunc main() int { return 0 }\n', '0')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('current=', result.stderr)


if __name__ == '__main__':
    unittest.main()
