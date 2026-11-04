"""The explicit legacy CLI must preserve sources through filesystem aliases."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class LegacyOutputAliasTests(unittest.TestCase):
    def test_legacy_build_rejects_source_aliases(self):
        for alias in ('same', 'symlink', 'hardlink', 'directory_symlink'):
            with self.subTest(alias=alias), tempfile.TemporaryDirectory(prefix='s-output-alias-') as directory:
                work = Path(directory)
                source = work / 'hello.s'
                original = (ROOT / 'test/cli/hello.s').read_bytes()
                source.write_bytes(original)
                output = work / 'output'
                if alias == 'same':
                    output = source
                elif alias == 'symlink':
                    output.symlink_to(source)
                elif alias == 'hardlink':
                    os.link(source, output)
                else:
                    (work / 'alias').symlink_to(work, target_is_directory=True)
                    output = work / 'alias/hello.s'
                result = subprocess.run(
                    [str(ROOT / 'bin/s'), 'build', '--legacy', str(source), '-o', str(output)],
                    capture_output=True, timeout=30,
                )
                self.assertNotEqual(result.returncode, 0, (alias, result.stderr.decode()))
                self.assertIn(b'output path must not overwrite input source', result.stderr)
                self.assertEqual(source.read_bytes(), original)


if __name__ == '__main__':
    unittest.main()
