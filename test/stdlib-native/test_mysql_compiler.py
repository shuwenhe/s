"""Regression for a real compiler blocker found by the MySQL client closure."""
import os, subprocess, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class QualifiedConstantTests(unittest.TestCase):
    def test_qualified_constant_assignment_to_reference_field(self):
        compiler=os.environ.get('S_TEST_COMPILER',str(ROOT/'bin/s_compiler'))
        with tempfile.TemporaryDirectory() as directory:
            work=Path(directory);source=work/'cursor.s';artifact=work/'cursor.sasm';binary=work/'cursor'
            source.write_text("""package fixture.errors
const protocol = 5
package fixture.wire
import "fixture.errors"
struct cursor { int code }
func fail(cursor* source) () { source.code = fixture.errors.protocol }
package main
import "fixture.wire"
func main() int {
    source := fixture.wire.cursor { code: 0 }
    fixture.wire.fail(source*)
    if source.code != 5 { return 1 }
    return 0
}
""")
            result=subprocess.run([compiler,'--compile-unit',str(artifact),str(source)],capture_output=True,timeout=60)
            self.assertEqual(result.returncode,0,result.stderr.decode())
            result=subprocess.run([compiler,'--emit-bin',str(artifact),str(binary)],capture_output=True,timeout=60)
            self.assertEqual(result.returncode,0,result.stderr.decode())
            self.assertEqual(subprocess.run([str(binary)],timeout=10).returncode,0)
            valid=source.read_text()
            for replacement in ('source.code = true', 'source.missing = fixture.errors.protocol'):
                with self.subTest(invalid=replacement):
                    source.write_text(valid.replace('source.code = fixture.errors.protocol',replacement))
                    artifact.write_text('keep')
                    result=subprocess.run([compiler,'--compile-unit',str(artifact),str(source)],capture_output=True,timeout=60)
                    self.assertNotEqual(result.returncode,0)
                    self.assertEqual(artifact.read_text(),'keep')

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

class MySQLClientCompilationTests(unittest.TestCase):
    def test_crud_dependency_closure_and_configuration_failures(self):
        with tempfile.TemporaryDirectory() as directory:
            binary=Path(directory)/'crud'
            result=subprocess.run(['python3',str(ROOT/'misc/scripts/build-openssl-client.py'),
                                   str(ROOT/'test/mysql/crud/main.s'),'-o',str(binary)],
                                  cwd=ROOT,capture_output=True,timeout=180)
            self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))
            # These cases fail before network access and require no credentials.
            for port,user,expected in [('0','s_test',1),('65536','s_test',1),
                                       ('not-a-port','s_test',1),('3306','',2)]:
                with self.subTest(port=port,user=user):
                    env=os.environ|{'MYSQL_PORT':port,'MYSQL_USER':user,'MYSQL_PASSWORD':'',
                                    'MYSQL_DATABASE':'s_test','MYSQL_TLS_HOST':'','MYSQL_CA':''}
                    run=subprocess.run([str(binary)],env=env,capture_output=True,timeout=10)
                    self.assertEqual(run.returncode,expected,(run.stdout,run.stderr))
                    self.assertNotIn(b'PASS MySQL CRUD',run.stdout)

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
