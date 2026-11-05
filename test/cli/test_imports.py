"""Public builds resolve actual library and same-package sources."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
DRIVER = ROOT / 'misc/scripts/s-driver.sh'


class PublicImportTests(unittest.TestCase):
    def invoke(self, *args, cwd):
        return subprocess.run(['sh', str(DRIVER), *map(str, args)], cwd=cwd, capture_output=True, timeout=60)

    def test_real_std_time_is_available_to_build_run_and_test(self):
        with tempfile.TemporaryDirectory(prefix='s public imports ') as directory:
            work = Path(directory)
            source = work / 'main.s'
            source.write_text('package main\nimport "std.time"\nfunc main() int { return std.time.sleep_ms(2).code }\n')
            for args in (('build', source, '-o', work / 'program'), ('run', source), ('test', source)):
                with self.subTest(command=args[0]):
                    result = self.invoke(*args, cwd=work)
                    self.assertEqual(result.returncode, 0, result.stderr)

    def test_local_import_and_same_package_helpers_and_dependency_alias_guard(self):
        with tempfile.TemporaryDirectory(prefix='s local imports ') as directory:
            work = Path(directory)
            (work / 'helper').mkdir()
            dependency = work / 'helper/value.s'
            dependency.write_text('package helper\nfunc value() int { return 40 }\n')
            source = work / 'main.s'
            source.write_text('package main\nimport "helper"\nfunc main() int { return helper.value() + local_value() }\n')
            (work / 'other.s').write_text('package main\nfunc local_value() int { return 2 }\n')
            result = self.invoke('build', source, '-o', work / 'program', cwd=work)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(subprocess.run([str(work / 'program')]).returncode, 42)
            before = dependency.read_bytes()
            result = self.invoke('build', source, '-o', dependency, cwd=work)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b'overwrite input', result.stderr)
            self.assertEqual(dependency.read_bytes(), before)

    def test_unresolved_import_fails_without_replacing_output(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            source = work / 'main.s'
            source.write_text('package main\nimport "missing.package"\nfunc main() int { return 0 }\n')
            output = work / 'program'
            output.write_bytes(b'keep previous executable\n')
            result = self.invoke('build', source, '-o', output, cwd=work)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(output.read_bytes(), b'keep previous executable\n')

    def test_entry_project_wins_over_unrelated_working_directory_package(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            for name, value in (('project', 40), ('unrelated', 99)):
                (work / name / 'helper').mkdir(parents=True)
                (work / name / 'helper/value.s').write_text('package helper\nfunc value() int { return ' + str(value) + ' }\n')
            source = work / 'project/main.s'
            source.write_text('package main\nimport "helper"\nfunc main() int { return helper.value() }\n')
            result = self.invoke('build', source, '-o', work / 'program', cwd=work / 'unrelated')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(subprocess.run([str(work / 'program')]).returncode, 40)


if __name__ == '__main__':
    unittest.main()
