"""Compile the actual service's pure validator without requiring a database."""
from pathlib import Path
import os,subprocess,tempfile,unittest
ROOT=Path(__file__).resolve().parents[2]
class UserValidation(unittest.TestCase):
 def test_validator_seed_and_native(self):
  with tempfile.TemporaryDirectory() as directory:
   work=Path(directory);source=work/'validator.s'
   # Extract the actual pure business boundary, not a test reimplementation.
   repository=(ROOT/'test/rest-users/repository.s').read_text()
   source.write_text('package main\nimport ("std.database"; "std.json")\n'+repository[repository.index('struct user_input'):])
   for seed in (True,False):
    with self.subTest(seed=seed):
     compiler=ROOT/('bin/s_seed' if seed else 'bin/s_compiler');artifact=work/'unit.ir';binary=work/'program'
     sources=[source,ROOT/'test/rest/users.s',ROOT/'src/std/json/json.s',ROOT/'src/std/database/types.s',ROOT/'src/result/result.s',ROOT/'src/option/option.s',ROOT/'src/prelude/prelude.s']
     for command in ([str(compiler),'--compile-native-unit' if seed else '--compile-unit',str(artifact),*map(str,sources)],[str(compiler),'--emit-standalone-amd64' if seed else '--emit-bin',str(artifact),str(binary)]):
      result=subprocess.run(command,cwd=ROOT,capture_output=True,env=os.environ|{'S_SOURCE_ROOT':str(ROOT)},timeout=120)
      self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))
     self.assertEqual(subprocess.run([str(binary)],timeout=10).returncode,0)
if __name__=='__main__':unittest.main(verbosity=2)
