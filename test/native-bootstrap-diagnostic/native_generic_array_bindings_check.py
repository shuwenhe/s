"""Generic dynamic-array inference, substitution and nominal result execution."""
from pathlib import Path
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[2]


class GenericArrayBindingsTests(unittest.TestCase):
    def test_array_elements_bind_type_arguments_and_preserve_negative_outputs(self):
        with tempfile.TemporaryDirectory(prefix='s-generic-array-bind-') as directory:
            work = Path(directory)
            cases = {
                'borrowed_array': 'func count[t](t[]* values) int { return 42 }\nfunc main() int { values := int[]{1}; return count(values*) }',
                'lexical_type_parameter_name': 'func identity[t](t t) t { return t }\nfunc main() int { return identity(42) }',
                'first': 'func first[t](t[] values) t { return values[0] }\nfunc main() int { return first(int[]{42}) }',
                'array_result': 'func identity[t](t[] values) t[] { return values }\nfunc main() int { values := identity(int[]{42}); return values[0] }',
                'record_pair': 'struct box[t] { t value }\nstruct error { int code }\nfunc wrap[t](t[] values) (box[t],error) { return box[t] { value: values[0] }, error { code: 0 } }\nfunc main() int { value, error := wrap(int[]{42}); return value.value + error.code }',
            }
            for name, body in cases.items():
                with self.subTest(name=name):
                    source, assembly, binary = work / 'main.s', work / 'main.sasm', work / 'program'
                    source.write_text('package main\n' + body + '\n')
                    for command in ([str(ROOT / 'bin/s_compiler'), '--compile-unit', str(assembly), str(source)],
                                    [str(ROOT / 'bin/s_compiler'), '--emit-bin', str(assembly), str(binary)]):
                        result = subprocess.run(command, capture_output=True, timeout=30)
                        self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(subprocess.run([str(binary)], timeout=5).returncode, 42)
            for body in ('func same[t](t[] a,t[] b) t { return a[0] }\nfunc main() int { return same(int[]{1},string[]{"x"}) }',
                         'func first[t](t[] a) t { return a[0] }\nfunc main() int { return first(42) }'):
                source.write_text('package main\n' + body + '\n')
                assembly.write_bytes(b'preserve\n')
                result = subprocess.run([str(ROOT / 'bin/s_compiler'), '--compile-unit', str(assembly), str(source)], capture_output=True, timeout=30)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(assembly.read_bytes(), b'preserve\n')


if __name__ == '__main__':
    unittest.main()
