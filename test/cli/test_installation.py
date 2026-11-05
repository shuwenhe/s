"""Relocated installations must compile without access to the checkout."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class InstallationTests(unittest.TestCase):
    def fixture(self, work):
        bundle = work / 'bundle'
        (bundle / 'bin').mkdir(parents=True)
        (bundle / 'misc/scripts').mkdir(parents=True)
        (bundle / 'src').mkdir()
        (bundle / 'makefile').write_text('# distribution fixture\n')
        shutil.copy2(ROOT / 'misc/scripts/s-driver.sh', bundle / 'bin/s')
        shutil.copy2(ROOT / 'misc/scripts/s-driver.sh', bundle / 'misc/scripts/s-driver.sh')
        shutil.copy2(ROOT / 'bin/s_compiler', bundle / 'bin/s_compiler')
        (bundle / 'VERSION').write_text('test-development\n')
        installer = ROOT / 'misc/scripts/install-distribution.py'
        if installer.exists():
            shutil.copy2(installer, bundle / 'misc/scripts/install-distribution.py')
        return bundle

    def invoke(self, bundle, prefix, *args):
        return subprocess.run(['python3', str(bundle / 'misc/scripts/install-distribution.py'),
                               '--prefix', str(prefix), *args], capture_output=True, timeout=60)

    def test_install_relocate_build_run_test_and_uninstall(self):
        with tempfile.TemporaryDirectory(prefix='s install ') as directory:
            work = Path(directory)
            bundle = self.fixture(work)
            prefix = work / 'prefix spaces'
            result = self.invoke(bundle, prefix)
            self.assertEqual(result.returncode, 0, result.stderr)
            moved = work / 'moved prefix'
            prefix.rename(moved)
            # Remove the original bundle so the installed driver cannot use it.
            shutil.rmtree(bundle)
            driver = moved / 'bin/s'
            env = os.environ | {'S_SOURCE_ROOT': '/nonexistent', 'PATH': '/usr/bin:/bin'}
            source = work / 'main.s'
            source.write_text('package main\nfunc main() int { return 0 }\n')
            for args in (('--version',), ('--help',), ('build', str(source), '-o', str(work / 'program')),
                         ('run', str(source)), ('test', str(source))):
                result = subprocess.run([str(driver), *args], cwd=work, env=env, capture_output=True, timeout=60)
                self.assertEqual(result.returncode, 0, (args, result.stderr))
            installed_root = driver.resolve().parents[1]
            result = self.invoke(installed_root, moved, '--uninstall')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(driver.exists())
            self.assertFalse(driver.is_symlink())

    def test_install_refuses_unowned_command_and_uninstall_preserves_it(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            bundle = self.fixture(work)
            prefix = work / 'prefix'
            (prefix / 'bin').mkdir(parents=True)
            command = prefix / 'bin/s'
            command.write_text('unrelated user command\n')
            for args in ((), ('--uninstall',)):
                result = self.invoke(bundle, prefix, *args)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(command.read_text(), 'unrelated user command\n')

    def test_library_only_upgrade_switches_to_new_version_and_retains_previous(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            bundle = self.fixture(work)
            library = bundle / 'src/library.s'
            library.write_text('version one\n')
            prefix = work / 'prefix'
            result = self.invoke(bundle, prefix)
            self.assertEqual(result.returncode, 0, result.stderr)
            first = (prefix / 'bin/s').resolve().parents[1]
            library.write_text('version two\n')
            result = self.invoke(bundle, prefix)
            self.assertEqual(result.returncode, 0, result.stderr)
            second = (prefix / 'bin/s').resolve().parents[1]
            self.assertNotEqual(first, second)
            self.assertEqual((first / 'src/library.s').read_text(), 'version one\n')
            self.assertEqual((second / 'src/library.s').read_text(), 'version two\n')

    def test_directory_symlink_cannot_create_a_nonportable_installation(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            bundle = self.fixture(work)
            external = work / 'external'
            external.mkdir()
            (external / 'library.s').write_text('external input\n')
            (bundle / 'src/library').symlink_to(external, target_is_directory=True)
            result = self.invoke(bundle, work / 'prefix')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b'symlink', result.stderr)
            self.assertFalse((work / 'prefix/bin/s').exists())

    def test_checkout_without_version_file_gets_development_identification(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            bundle = self.fixture(work)
            (bundle / 'VERSION').unlink()
            result = self.invoke(bundle, work / 'prefix')
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(work / 'prefix/bin/s'), '--version'], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(b'S compiler dev-', result.stdout)


if __name__ == '__main__':
    unittest.main()
