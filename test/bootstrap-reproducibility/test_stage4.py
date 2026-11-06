"""Test bootstrap orchestration; fixture compilers do not certify selfhosting."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
DRIVER = ROOT / 'src/cmd/dist/native-bootstrap-no-manifest.sh'

class Stage4Tests(unittest.TestCase):
    def run_controller(self, mode='ok'):
        work = Path(self.directory.name)
        repo, out = work / 'repo', work / 'out'
        for path in ('bin', 'src/cmd/dist/checks', 'src/cmd/compile', 'misc/scripts'):
            (repo / path).mkdir(parents=True, exist_ok=True)
        (repo / 'src/cmd/compile/main.s').write_text('package main\n')
        closure = repo / 'src/cmd/dist/source_closure.sh'
        closure.write_text('#!/bin/sh\nprintf "%s\\n" src/cmd/compile/main.s > "$2"\n')
        closure.chmod(0o755)
        (repo / 'misc/scripts/verify_true_selfhost.sh').write_text('exit 0\n')
        (repo / 'src/cmd/dist/checks/selfhost-execution.sh').write_text('echo "$1" >> "$S_TEST_EXECUTIONS"\n')
        seed = repo / 'bin/s_seed'
        seed.write_text('''#!/bin/sh
case "$1" in
 --compile-native-unit) echo seed-ir > "$2" ;;
 --emit-standalone-amd64) cp "$S_TEST_COMPILER" "$3"; chmod +x "$3" ;;
 *) exit 91 ;;
esac
''')
        seed.chmod(0o755)
        compiler = work / 'compiler'
        compiler.write_text('''#!/bin/sh
echo "$0 $*" >> "$S_TEST_CALLS"
case "$1" in
 --compile-unit)
  case "$2:$S_TEST_MODE" in *stage4.sasm:fail) exit 47 ;; esac
  echo '# S-NATIVE-AMD64-V1' > "$2"
  case "$2:$S_TEST_MODE" in *stage4.sasm:diverge) echo changed >> "$2" ;; esac ;;
 --emit-bin) cp "$S_TEST_COMPILER" "$3"; chmod +x "$3" ;;
 *) exit 92 ;;
esac
''')
        compiler.chmod(0o755)
        out.mkdir(exist_ok=True)
        (out / '.complete').touch()
        env = os.environ | {'S_SOURCE_ROOT': str(repo), 'S_TEST_COMPILER': str(compiler),
                            'S_TEST_MODE': mode, 'S_TEST_CALLS': str(work / 'calls'),
                            'S_TEST_EXECUTIONS': str(work / 'executions')}
        result = subprocess.run(['bash', str(DRIVER), str(out)], env=env, capture_output=True, text=True, timeout=20)
        return result, out, work

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='s-stage4-controller-')
        self.addCleanup(self.directory.cleanup)

    def test_stage4_compilation_and_execution(self):
        result, out, work = self.run_controller()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((out / 'stage4').is_file(), result.stdout)
        self.assertEqual((out / 'stage3').read_bytes(), (out / 'stage4').read_bytes())
        self.assertIn(str(out / 'stage4'), (work / 'executions').read_text())
        self.assertTrue((out / '.complete').exists())

    def test_stage4_failure_invalidates_completion(self):
        result, out, _ = self.run_controller('fail')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertFalse((out / '.complete').exists())

    def test_stage4_divergence_invalidates_completion(self):
        result, out, _ = self.run_controller('diverge')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertFalse((out / '.complete').exists())

    def test_make_installs_stage4_with_public_driver(self):
        result, out, work = self.run_controller()
        self.assertEqual(result.returncode, 0, result.stderr)
        repo, prefix = work / 'repo', work / 'installed'
        shutil.copy2(ROOT / 'makefile', repo / 'makefile')
        shutil.copy2(DRIVER, repo / 'src/cmd/dist/native-bootstrap-no-manifest.sh')
        for name in ('s-driver.sh', 'install-distribution.py'):
            shutil.copy2(ROOT / 'misc/scripts' / name, repo / 'misc/scripts' / name)
        # The fixture seed is already built; make must not rebuild or install
        # a development compiler after completing the bootstrap.
        os.utime(repo / 'bin/s_seed', None)
        env = os.environ | {'S_TEST_COMPILER': str(work / 'compiler'), 'S_TEST_MODE': 'ok',
                            'S_TEST_CALLS': str(work / 'calls'),
                            'S_TEST_EXECUTIONS': str(work / 'executions')}
        result = subprocess.run(['make', 'selfhost-install', f'PREFIX={prefix}',
                                 f'NATIVE_BOOTSTRAP_IMPORTS_DIR={out}'],
                                cwd=repo, env=env, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        installed = (prefix / 'bin/s').resolve()
        self.assertEqual(installed.read_bytes(), (ROOT / 'misc/scripts/s-driver.sh').read_bytes())
        self.assertEqual((installed.parent / 's_compiler').read_bytes(), (out / 'stage4').read_bytes())

if __name__ == '__main__':
    unittest.main()
