"""The production compiler manifest must include executable extension definitions."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SEED = ROOT / 'bin/s_seed'
EXTENSION = 'src/cmd/compile/internal/codegen/native_runtime_extensions.s'


class CompilerExtensionManifestTests(unittest.TestCase):
    def test_manifest_supplies_real_extension_callees_to_borrowed_compiler_code(self):
        manifest = subprocess.run(['make', '-s', 'compiler-source-list'], cwd=ROOT,
                                  capture_output=True, text=True, timeout=30)
        self.assertEqual(manifest.returncode, 0, manifest.stderr)
        sources = [ROOT / line for line in manifest.stdout.splitlines() if line == EXTENSION]
        with tempfile.TemporaryDirectory(prefix='s-compiler-extension-manifest-') as directory:
            work = Path(directory)
            source, intermediate, binary = work / 'main.s', work / 'main.ir', work / 'main'
            source.write_text('''package compile.internal
struct state { string target }
func assign(state* value, string name) { value.target = amd64_native_extension_target(name) }
func main() int {
    value := state { target: "" }
    assign(value*,"__sys_socket")
    if value.target != "s_ext_socket" { return 1 }
    if amd64_native_extension_target("unknown") != "" { return 2 }
    return 42
}
''')
            for command in ([str(SEED), '--compile-native-unit', str(intermediate),
                             *map(str, sources), str(source)],
                            [str(SEED), '--emit-standalone-amd64', str(intermediate), str(binary)]):
                result = subprocess.run(command, cwd=ROOT, capture_output=True,
                                        env=os.environ | {'S_SOURCE_ROOT': str(ROOT)}, timeout=60)
                self.assertEqual(result.returncode, 0, result.stderr.decode())
            self.assertEqual(subprocess.run([str(binary)], timeout=10).returncode, 42)
            # Unresolved callees must still fail closed and preserve old output.
            intermediate.write_text(intermediate.read_text().replace(
                '|amd64_native_extension_target|', '|missing_extension_target|'))
            binary.write_bytes(b'previous artifact\n')
            result = subprocess.run([str(SEED), '--emit-standalone-amd64', str(intermediate),
                                     str(binary)], cwd=ROOT, capture_output=True, timeout=60)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(binary.read_bytes(), b'previous artifact\n')


if __name__ == '__main__':
    unittest.main()
