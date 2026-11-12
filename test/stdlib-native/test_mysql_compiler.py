"""Regression for a real compiler blocker found by the MySQL client closure."""
import os, subprocess, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class QualifiedConstantTests(unittest.TestCase):
    def test_cross_package_constant_and_local_field_share_spelling(self):
        compiler=os.environ.get('S_TEST_COMPILER',str(ROOT/'bin/s_compiler'))
        with tempfile.TemporaryDirectory() as directory:
            work=Path(directory);source=work/'const.s';binary=work/'const'
            source.write_text('''package fixture.constants
const protocol_error = 5
package main
import "fixture.constants"
struct local { int protocol_error }
enum nullable { none, some(int) }
func empty() nullable { return main.nullable.none }
func main() int {
    empty_value := empty()
    switch empty_value { nullable.none : {}, _ : { return 3 }, }
    value := local { protocol_error: 7 }
    if value.protocol_error != 7 { return 1 }
    if fixture.constants.protocol_error != 5 { return 2 }
    return 0
}
''')
            # Use the normal compile-unit artifact path, never a hosted fallback.
            artifact=work/'const.sasm'
            result=subprocess.run([compiler,'--compile-unit',str(artifact),str(source)],capture_output=True,timeout=60)
            self.assertEqual(result.returncode,0,result.stderr.decode())
            result=subprocess.run([compiler,'--emit-bin',str(artifact),str(binary)],capture_output=True,timeout=60)
            self.assertEqual(result.returncode,0,result.stderr.decode())
            self.assertEqual(subprocess.run([str(binary)]).returncode,0)

class TLSClientStartupTests(unittest.TestCase):
    def test_c_startup_initializes_native_environment(self):
        with tempfile.TemporaryDirectory() as directory:
            work=Path(directory);source=work/'env.s';binary=work/'env'
            source.write_text('''package main
extern "intrinsic" func runtime_env_get(string key, string fallback) string
func main() int {
    if runtime_env_get("S_MYSQL_STARTUP_TEST","missing") != "present" { return 99 }
    return 0
}
''')
            result=subprocess.run(['python3',str(ROOT/'misc/scripts/build-openssl-client.py'),str(source),'-o',str(binary)],cwd=ROOT,capture_output=True,timeout=60)
            self.assertEqual(result.returncode,0,result.stderr.decode())
            result=subprocess.run([str(binary)],env=os.environ|{'S_MYSQL_STARTUP_TEST':'present'})
            self.assertEqual(result.returncode,0)

if __name__=='__main__':unittest.main()
