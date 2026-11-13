"""Real native and seed compilation of bounded JSON contracts."""
from pathlib import Path
import subprocess
import resource
import tempfile
import unittest
def memory_cap():
    resource.setrlimit(resource.RLIMIT_AS, (268435456, 268435456))
ROOT = Path(__file__).resolve().parents[2]
class RestJSON(unittest.TestCase):
    def test_json_native_and_seed(self):
        for seed in (True, False):
            with self.subTest(seed=seed), tempfile.TemporaryDirectory() as directory:
                ir = Path(directory)/'unit.ir'
                binary = Path(directory)/'program'
                compiler = ROOT/('bin/s_seed' if seed else 'bin/s_compiler')
                sources = [ROOT/'test/rest/json.s', *sorted((ROOT/'src/std/json').glob('*.s')), ROOT/'src/result/result.s', ROOT/'src/prelude/prelude.s']
                for command in ([str(compiler), '--compile-native-unit' if seed else '--compile-unit', str(ir), *map(str,sources)], [str(compiler), '--emit-standalone-amd64' if seed else '--emit-bin', str(ir), str(binary)]):
                    r = subprocess.run(command,cwd=ROOT,capture_output=True,timeout=120)
                    self.assertEqual(r.returncode,0,(command,r.stdout,r.stderr))
                r = subprocess.run([str(binary)],capture_output=True,timeout=20,preexec_fn=memory_cap)
                self.assertEqual(r.returncode,0,(r.stdout,r.stderr))
                self.assertIn(b'json: PASS',r.stdout)
                print(('seed' if seed else 'native')+': '+r.stdout.decode().strip())
if __name__ == '__main__': unittest.main()
