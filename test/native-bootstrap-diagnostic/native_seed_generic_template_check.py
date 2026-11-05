"""Abstract templates defer dependent checks; concrete instances remain checked."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[2]


class SeedGenericTemplateTests(unittest.TestCase):
    def test_symbolic_field_arguments_keep_packages_and_parameter_names(self):
        with tempfile.TemporaryDirectory(prefix='s-seed-symbolic-fields-') as directory:
            work = Path(directory)
            source, intermediate, binary = work / 'main.s', work / 'main.ir', work / 'program'
            left = work / 'left.s'
            right = work / 'right.s'
            left.write_text('package left\nstruct box[t] { t value }\n')
            right.write_text('package right\nstruct box[t] { int count }\n')
            source.write_text('package main\nimport ("left"; "right")\nfunc read[u](left.box[u][] root) u { return root[0].value }\nfunc count[u](right.box[u][] root) int { return root[0].count }\nfunc main() int {\n    first := left.box[int] { value: 42 }\n    second := right.box[string] { count: 0 }\n    return read([first]) + count([second])\n}\n')
            for command in ([str(ROOT / 'bin/s_seed'),'--compile-native-unit',str(intermediate),str(left),str(right),str(source)],
                            [str(ROOT / 'bin/s_seed'),'--emit-standalone-amd64',str(intermediate),str(binary)]):
                result = subprocess.run(command,cwd=ROOT,env=os.environ | {'S_SOURCE_ROOT':str(ROOT)},capture_output=True,timeout=30)
                self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(subprocess.run([str(binary)],timeout=5).returncode,42)

    def test_unrelated_same_named_type_cannot_hide_fixed_definition_error(self):
        with tempfile.TemporaryDirectory(prefix='s-symbolic-nominal-') as directory:
            work = Path(directory)
            left,right,source,output = (work / name for name in ('left.s','right.s','main.s','main.ir'))
            left.write_text('package left\nstruct inner[t] { int count }\nstruct outer[t] { inner[t] item }\n'
                            'func bad[u](outer[u] value) string { return value.item.count }\n')
            right.write_text('package right\nstruct inner[t] { string count }\n')
            source.write_text('package main\nfunc main() int { return 0 }\n')
            for inputs in ((left,source),(left,right,source)):
                output.write_bytes(b'previous IR\n')
                result = subprocess.run([str(ROOT / 'bin/s_seed'),'--compile-native-unit',str(output),*map(str,inputs)],capture_output=True,timeout=30)
                self.assertNotEqual(result.returncode,0,inputs)
                self.assertEqual(output.read_bytes(),b'previous IR\n')
                self.assertIn(b'return',result.stderr)

    def test_recursive_record_template_and_concrete_body_validation(self):
        with tempfile.TemporaryDirectory(prefix='s-seed-template-') as directory:
            work = Path(directory)
            source, intermediate, binary = work / 'main.s', work / 'main.ir', work / 'program'
            common = ('struct node[t] { int count, node[t][] left }\n'
                      'func probe[t](node[t][] root) int { value := root[0]; return value.left[0].count }\n')
            for body, wanted in ((common + 'func main() int { return 0 }',0),
                                 (common + 'func main() int { leaf := node[int] { count: 42 }; parent := node[int] { left: [leaf] }; return probe([parent]) }',42)):
                source.write_text('package main\n' + body + '\n')
                for command in ([str(ROOT / 'bin/s_seed'),'--compile-native-unit',str(intermediate),str(source)],
                                [str(ROOT / 'bin/s_seed'),'--emit-standalone-amd64',str(intermediate),str(binary)]):
                    result = subprocess.run(command,cwd=ROOT,env=os.environ | {'S_SOURCE_ROOT':str(ROOT)},capture_output=True,timeout=30)
                    self.assertEqual(result.returncode,0,result.stderr)
                self.assertEqual(subprocess.run([str(binary)],timeout=5).returncode,wanted)
            # Definitions still reject errors independent of T, even unused.
            for body in ('func bad[t](t value) int { return "wrong" }',
                         'func bad[t](t value) int { return missing_name }',
                         'func bad[t](t value) int { return 42[0] }',
                         'struct fixed[t] { int count }\nfunc bad[t](fixed[t] value) int { return value.count[0] }'):
                source.write_text('package main\n' + body + '\nfunc main() int { return 0 }\n')
                rejected = work / 'rejected.ir'
                rejected.write_bytes(b'previous IR\n')
                result = subprocess.run([str(ROOT / 'bin/s_seed'),'--compile-native-unit',str(rejected),str(source)],capture_output=True,timeout=30)
                self.assertNotEqual(result.returncode,0,body)
                self.assertEqual(rejected.read_bytes(),b'previous IR\n')
            # Exercise the actual IR reader: malformed generic ARRAY_NEW
            # metadata must fail atomically, including raw borrowed elements.
            valid_ir = intermediate.read_text()
            self.assertIn('ARRAY_NEW|',valid_ir)
            for bad_type in ('main.node[int,][]','main.node[,int][]','main.node[int][]*',
                             'main.node[int*][]','main.node[int[]','main.node[int][];bad'):
                lines = []
                for line in valid_ir.splitlines():
                    if line.startswith('ARRAY_NEW|'):
                        fields = line.split('|')
                        fields[2] = bad_type
                        line = '|'.join(fields)
                    lines.append(line)
                intermediate.write_text('\n'.join(lines) + '\n')
                binary.write_bytes(b'previous executable\n')
                result = subprocess.run([str(ROOT / 'bin/s_seed'),'--emit-standalone-amd64',str(intermediate),str(binary)],
                                        cwd=ROOT,capture_output=True,timeout=30)
                self.assertNotEqual(result.returncode,0,bad_type)
                self.assertEqual(binary.read_bytes(),b'previous executable\n')
            source.write_text('''package main
struct node[t] { t left }
func invalid[t](node[t][] root) int { value := root[0]; return value.left[0] }
func main() int { value := node[int] { left: 42 }; return invalid([value]) }
''')
            intermediate.write_bytes(b'previous IR\n')
            result = subprocess.run([str(ROOT / 'bin/s_seed'),'--compile-native-unit',str(intermediate),str(source)],capture_output=True,timeout=30)
            self.assertNotEqual(result.returncode,0)
            self.assertEqual(intermediate.read_bytes(),b'previous IR\n')
            self.assertIn(b'index',result.stderr)


if __name__ == '__main__':
    unittest.main()
