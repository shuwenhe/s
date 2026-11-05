"""Reference specialization must preserve referents and mutability safely."""
from pathlib import Path
import os
import re
import resource
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
COMPILER = Path(os.environ.get('S_TEST_COMPILER', ROOT / 'bin/s_compiler')).resolve()


def limits():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


class ReferenceInstantiationTests(unittest.TestCase):
    def test_invalid_reference_field_initializer_is_diagnosed_without_crashing(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            source, output = work / 'main.s', work / 'output.sasm'
            for reference in ('&int', '&mut int', 'int*'):
                with self.subTest(reference=reference):
                    source.write_text('package main\nstruct item { ' + reference + ' value }\n'
                                      'func main() int { x := item { value: 42 }; return x.value }\n')
                    output.write_bytes(b'previous output\n')
                    result = subprocess.run([str(COMPILER), '--compile-unit', str(output), str(source)],
                                            capture_output=True, timeout=30, preexec_fn=limits)
                    self.assertIn(result.returncode, (1, 2), result.stderr)
                    self.assertIn(b'canonical semantic', result.stderr)
                    self.assertEqual(output.read_bytes(), b'previous output\n')

    def test_actual_specialization_helpers_preserve_reference_prefix_and_generic(self):
        semantic = (ROOT / 'src/cmd/compile/internal/semantic/semantic.s').read_text()
        functions = []
        for name in ('instantiate_type', 'type_contains_generic', 'is_generic_name',
                     'strip_array_prefix', 'array_prefix_text', 'lookup_name_type',
                     'is_unknown', 'semantic_starts_with'):
            match = re.search(r'^func ' + name + r'\(.*?(?=^func |\Z)', semantic, re.M | re.S)
            self.assertIsNotNone(match, name)
            functions.append(match[0])
        binding = re.search(r'^struct type_binding \{.*?^\}', semantic, re.M | re.S)[0]
        source = '''package compile.internal.semantic
import ("compile.internal.ast"; "compile.internal.typesys"; "std.option"; "std.prelude")
''' + binding + '\n' + '\n'.join(functions) + '''
func main() int {
    names := string[]{"T"}
    bindings := type_binding[]()
    bindings.push(type_binding { name: "T", type_name: "int" })
    if instantiate_type("&T", names, bindings) != "&int" { return 10 }
    if instantiate_type("&mut T", names, bindings) != "&mutint" { return 11 }
    if instantiate_type("T*", names, bindings) != "&mutint" { return 12 }
    if instantiate_type("&int", names, bindings) != "&int" { return 13 }
    if instantiate_type("&mut int", names, bindings) != "&mutint" { return 14 }
    if !type_contains_generic("&T", names) { return 15 }
    if !type_contains_generic("&mut T", names) { return 16 }
    if !type_contains_generic("T*", names) { return 17 }
    if type_contains_generic("&int", names) { return 18 }
    if type_contains_generic("&mut int", names) { return 19 }
    if instantiate_type("[]&T", names, bindings) != "[]&int" { return 20 }
    return 42
}
'''
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            (work / 'main.s').write_text(source)
            sources = ['src/option/option.s', 'src/result/result.s', 'src/prelude/prelude.s',
                       'src/fs/fs.s', 'src/cmd/compile/internal/ast/ast.s',
                       'src/cmd/compile/internal/typesys/typesys.s']
            result = subprocess.run([str(ROOT / 'bin/s_seed'), '--compile-native-unit', str(work / 'main.ir'),
                                     *map(str, (ROOT / p for p in sources)), str(work / 'main.s')],
                                    capture_output=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(ROOT / 'bin/s_seed'), '--emit-standalone-amd64',
                                     str(work / 'main.ir'), str(work / 'main')], cwd=ROOT,
                                    env=os.environ | {'S_SOURCE_ROOT': str(ROOT)}, capture_output=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(work / 'main')], capture_output=True, timeout=30, preexec_fn=limits)
            self.assertEqual(result.returncode, 42, result.stderr)


if __name__ == '__main__':
    unittest.main()
