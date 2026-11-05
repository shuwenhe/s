"""Exercise the public driver with real native programs and failure statuses."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
DRIVER = Path(os.environ.get('S_TEST_DRIVER', ROOT / 'misc/scripts/s-driver.sh')).resolve()


class DistributionCliTests(unittest.TestCase):
    def invoke(self, *args, cwd=None, env=None):
        return subprocess.run(['sh', str(DRIVER), *map(str, args)], cwd=cwd,
                              env=env, capture_output=True, timeout=60)

    def test_version_and_help(self):
        version = self.invoke('--version')
        self.assertEqual(version.returncode, 0, version.stderr)
        self.assertRegex(version.stdout, rb'^S compiler \S+')
        help_result = self.invoke('--help')
        self.assertEqual(help_result.returncode, 0)
        for command in (b'--version', b's build', b's run', b's test'):
            self.assertIn(command, help_result.stdout + help_result.stderr)

    def test_run_forwards_arguments_and_exit_status_without_output_artifacts(self):
        with tempfile.TemporaryDirectory(prefix='s run spaces ') as directory:
            work = Path(directory)
            source = work / 'main source.s'
            source.write_text('package main\nfunc main(int value) int { return value * 3 + 4 }\n')
            temporary = work / 'temporary'
            temporary.mkdir()
            env = os.environ | {'TMPDIR': str(temporary)}
            result = self.invoke('run', source, '--', '7', cwd=work, env=env)
            self.assertEqual(result.returncode, 25, result.stderr)
            self.assertEqual(list(temporary.iterdir()), [])
            self.assertEqual(sorted(p.name for p in work.iterdir()), ['main source.s', 'temporary'])

    def test_test_discovers_files_and_propagates_compile_and_runtime_failure(self):
        with tempfile.TemporaryDirectory(prefix='s tests ') as directory:
            work = Path(directory)
            passing = work / 'passing_test.s'
            passing.write_text('package main\nfunc main() int { return 0 }\n')
            result = self.invoke('test', cwd=work)
            self.assertEqual(result.returncode, 0, result.stderr)
            failing = work / 'failing_test.s'
            failing.write_text('package main\nfunc main() int { return 7 }\n')
            result = self.invoke('test', passing, failing, cwd=work)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b'failing_test.s', result.stdout + result.stderr)
            failing.write_text('package main\nfunc main() int { return unknown_name }\n')
            result = self.invoke('test', passing, failing, cwd=work)
            self.assertNotEqual(result.returncode, 0)

    def test_test_empty_and_invalid_commands_fail_without_clobber(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            for args in (('test',), ('run',), ('run', 'missing.s'), ('fmt',)):
                result = self.invoke(*args, cwd=work)
                self.assertNotEqual(result.returncode, 0, args)
            self.assertEqual(list(work.iterdir()), [])


if __name__ == '__main__':
    unittest.main()
