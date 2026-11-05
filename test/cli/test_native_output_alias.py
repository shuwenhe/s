"""All public compiler outputs must preserve every aliased input file.

Removing the compiler entry guard must reproduce source data loss, including
an output alias of a later --compile-unit input.
"""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
COMPILER = Path(os.environ.get('S_TEST_COMPILER', ROOT / 'bin/s_compiler')).resolve()
SOURCE = b'package main\nfunc main() int { return 0 }\n'


class NativeOutputAliasTests(unittest.TestCase):
    def test_outputs_reject_all_source_aliases(self):
        modes = ('--emit-mir', '--emit-c', '--emit-lowered-view',
                 '--emit-amd64', '--emit-native-object', '--canonical-ast-check',
                 '--compile-unit', 'build', 'default')
        for mode in modes:
            for alias in ('same', 'symlink', 'hardlink', 'directory_symlink'):
                with self.subTest(mode=mode, alias=alias), tempfile.TemporaryDirectory() as directory:
                    work = Path(directory)
                    source = work / 'main.s'
                    source.write_bytes(SOURCE)
                    output = work / 'output'
                    if alias == 'same':
                        output = source
                    elif alias == 'symlink':
                        output.symlink_to(source)
                    elif alias == 'hardlink':
                        os.link(source, output)
                    else:
                        (work / 'alias').symlink_to(work, target_is_directory=True)
                        output = work / 'alias/main.s'
                    if mode == '--compile-unit':
                        first = work / 'first.s'
                        first.write_text('package main\nfunc helper() int { return 1 }\n')
                        args = [mode, str(output), str(first), str(source)]
                    elif mode == 'default':
                        args = [str(source), str(output)]
                    else:
                        args = [mode, str(source), str(output)]
                    result = subprocess.run([str(COMPILER), *args], capture_output=True, timeout=60)
                    self.assertEqual(source.read_bytes(), SOURCE, (mode, alias, result.stderr))
                    self.assertNotEqual(result.returncode, 0, (mode, alias))
                    self.assertIn(b'overwrite input', result.stderr)

    def test_emit_bin_rejects_assembly_alias(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            source = work / 'main.s'
            source.write_bytes(SOURCE)
            assembly = work / 'main.sasm'
            emitted = subprocess.run([str(COMPILER), '--emit-amd64', str(source), str(assembly)], capture_output=True, timeout=60)
            self.assertEqual(emitted.returncode, 0, emitted.stderr)
            original = assembly.read_bytes()
            output = work / 'alias.sasm'
            os.link(assembly, output)
            result = subprocess.run([str(COMPILER), '--emit-bin', str(assembly), str(output)], capture_output=True, timeout=60)
            self.assertEqual(assembly.read_bytes(), original)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b'overwrite input', result.stderr)


if __name__ == '__main__':
    unittest.main()
