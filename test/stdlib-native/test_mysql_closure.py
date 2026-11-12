"""External client entries must retain siblings without importing other programs."""
import os, subprocess, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class MySQLClosureTests(unittest.TestCase):
    def test_external_entry_resolves_mysql_and_only_its_main_package(self):
        with tempfile.TemporaryDirectory() as directory:
            work=Path(directory);entry=work/'main.s';sibling=work/'helper.s';closure=work/'sources'
            entry.write_text('package main\nimport "std.mysql"\nfunc main() int { return helper() }\n')
            sibling.write_text('package main\nfunc helper() int { return 0 }\n')
            result=subprocess.run(['sh',str(ROOT/'src/cmd/dist/source_closure.sh'),str(entry),str(closure)],cwd=ROOT,env=os.environ|{'S_SOURCE_ROOT':str(ROOT)},capture_output=True,text=True,timeout=30)
            self.assertEqual(result.returncode,0,result.stderr)
            paths=closure.read_text().splitlines()
            self.assertIn(str(entry),paths);self.assertIn(str(sibling),paths)
            self.assertIn('src/std/mysql/client.s',paths)
            self.assertNotIn('src/cmd/main.s',paths)
            self.assertNotIn('src/std/database/interfaces.s',paths)
if __name__=='__main__':unittest.main()
