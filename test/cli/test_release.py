"""Release bytes must be repeatable and certification must fail closed."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ReleaseTests(unittest.TestCase):
    def fixture(self, work):
        repository = work / 'source'
        (repository / 'misc/scripts').mkdir(parents=True)
        (repository / 'bin').mkdir()
        for name in ('build-release.py', 's-driver.sh', 'install-distribution.py'):
            if (ROOT / 'misc/scripts' / name).exists():
                shutil.copy2(ROOT / 'misc/scripts' / name, repository / 'misc/scripts' / name)
        shutil.copy2(ROOT / 'bin/s_compiler', repository / 'bin/s_compiler')
        (repository / 'VERSION').write_text('0.1.0-dev\n')
        (repository / 'makefile').write_text('# fixture\n')
        (repository / '.gitignore').write_text('bin/\n.bootstrap/\n')
        subprocess.run(['git', 'init', '-q', str(repository)], check=True)
        subprocess.run(['git', '-C', str(repository), 'add', '.'], check=True)
        subprocess.run(['git', '-C', str(repository), '-c', 'user.name=Release test',
                        '-c', 'user.email=release-test@example.invalid', 'commit', '-qm', 'fixture'], check=True)
        return repository

    def invoke(self, repository, output, *args):
        return subprocess.run(['python3', str(repository / 'misc/scripts/build-release.py'),
                               '--output', str(output), *args], capture_output=True, timeout=60)

    def test_candidate_is_reproducible_and_excludes_ignored_inputs(self):
        with tempfile.TemporaryDirectory(prefix='s release ') as directory:
            work = Path(directory)
            repository = self.fixture(work)
            (repository / '.bootstrap').mkdir()
            (repository / '.bootstrap/untrusted').write_text('ignored content')
            outputs = [work / 'one', work / 'two']
            for output in outputs:
                result = self.invoke(repository, output, '--candidate')
                self.assertEqual(result.returncode, 0, result.stderr)
                report = json.loads((output / 'release.json').read_text())
                self.assertEqual(report['certification'], 'NOT CERTIFIED')
                for line in (output / 'SHA256SUMS').read_text().splitlines():
                    wanted, name = line.split('  ', 1)
                    self.assertEqual(hashlib.sha256((output / name).read_bytes()).hexdigest(), wanted)
            archives = sorted(outputs[0].glob('*.tar.gz'))
            self.assertTrue(archives)
            for archive in archives:
                self.assertEqual(archive.read_bytes(), (outputs[1] / archive.name).read_bytes())
                with tarfile.open(archive) as stream:
                    self.assertFalse(any('/.git/' in n or '/.bootstrap/' in n for n in stream.getnames()))
            refused = self.invoke(repository, outputs[0], '--candidate')
            self.assertNotEqual(refused.returncode, 0)

    def test_official_release_requires_license_and_full_acceptance(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            repository = self.fixture(work)
            acceptance = work / 'acceptance'
            acceptance.mkdir()
            (acceptance / 'ACCEPTED.json').write_text('{}')
            result = self.invoke(repository, work / 'official', '--acceptance', acceptance)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b'LICENSE', result.stderr)
            self.assertFalse(list((work / 'official').glob('*.tar.gz')))

    def test_committed_modes_determine_archive_even_when_git_ignores_chmod(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            repository = self.fixture(work)
            subprocess.run(['git', '-C', str(repository), 'config', 'core.fileMode', 'false'], check=True)
            first, second = work / 'one', work / 'two'
            result = self.invoke(repository, first, '--candidate')
            self.assertEqual(result.returncode, 0, result.stderr)
            driver = repository / 'misc/scripts/s-driver.sh'
            driver.chmod(driver.stat().st_mode ^ 0o111)
            result = self.invoke(repository, second, '--candidate')
            self.assertEqual(result.returncode, 0, result.stderr)
            for archive in first.glob('*.tar.gz'):
                self.assertEqual(archive.read_bytes(), (second / archive.name).read_bytes())


if __name__ == '__main__':
    unittest.main()
