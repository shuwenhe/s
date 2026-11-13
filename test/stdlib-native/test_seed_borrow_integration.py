"""Imported mutable APIs retain nominal owners from transparent tuple bindings."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SeedImportedBorrowTests(unittest.TestCase):
    def test_complete_http_closed_server_borrow(self):
        sources = [ROOT/'src/std/tcp.s', ROOT/'src/std/time.s',
                   ROOT/'src/result/result.s', ROOT/'src/prelude/prelude.s',
                   *sorted((ROOT/'src/std/http').glob('*.s')),
                   ROOT/'test/http/seed-borrow-repro/main.s']
        for compiler in (ROOT/'bin/s_seed', ROOT/'bin/s_compiler'):
            with self.subTest(compiler=compiler.name), tempfile.TemporaryDirectory() as directory:
                seed = compiler.name == 's_seed'
                artifact, binary = Path(directory)/'unit.ir', Path(directory)/'program'
                for command in (
                    [str(compiler), '--compile-native-unit' if seed else '--compile-unit',
                     str(artifact), *map(str, sources)],
                    [str(compiler), '--emit-standalone-amd64' if seed else '--emit-bin',
                     str(artifact), str(binary)],
                ):
                    result = subprocess.run(command, cwd=ROOT, capture_output=True,
                                            env=os.environ|{'S_SOURCE_ROOT':str(ROOT)}, timeout=120)
                    self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
                self.assertEqual(subprocess.run([str(binary)], timeout=10).returncode, 0)

    def test_package_local_functions_with_same_leaf_keep_signature_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            work=Path(directory)
            (work/'left.s').write_text('package left\nfunc local_port(int value) int { return value + 1 }\nfunc own() int { return local_port(40) }\n')
            (work/'right.s').write_text('package right\nfunc local_port(string value) int { return len(value) }\nfunc own() int { return local_port("x") }\n')
            (work/'main.s').write_text('package main\nimport ("left"; "right")\nfunc main() int { if left.own() + right.own() != 42 { return 1 }\nreturn 0 }\n')
            for compiler in (ROOT/'bin/s_seed', ROOT/'bin/s_compiler'):
                seed=compiler.name=='s_seed'
                artifact,binary=work/'unit.ir',work/'program'
                command=[str(compiler),'--compile-native-unit' if seed else '--compile-unit',str(artifact),str(work/'left.s'),str(work/'right.s'),str(work/'main.s')]
                with self.subTest(compiler=compiler.name,variant='valid'):
                    result=subprocess.run(command,cwd=ROOT,capture_output=True,timeout=60)
                    self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))
                    emitted=subprocess.run([str(compiler),'--emit-standalone-amd64' if seed else '--emit-bin',str(artifact),str(binary)],cwd=ROOT,env=os.environ|{'S_SOURCE_ROOT':str(ROOT)},capture_output=True,timeout=60)
                    self.assertEqual(emitted.returncode,0,emitted.stderr)
                    self.assertEqual(subprocess.run([str(binary)],timeout=10).returncode,0)
                original=(work/'left.s').read_text()
                for name,bad in [('duplicate',original+'func local_port(int value) int { return value }\n'),
                                 ('wrong-type',original.replace('local_port(40)','local_port(true)')),
                                 ('shadow',original.replace('return local_port(40)', 'local_port := 0; return local_port(40)'))]:
                    if name == 'shadow' and not seed:
                        continue  # Native lexical-call shadowing is outside this Seed regression.
                    with self.subTest(compiler=compiler.name,variant=name):
                        (work/'left.s').write_text(bad)
                        artifact.write_bytes(b'previous output\n')
                        rejected=subprocess.run(command,cwd=ROOT,capture_output=True,timeout=60)
                        self.assertNotEqual(rejected.returncode,0,rejected.stderr)
                        self.assertEqual(artifact.read_bytes(),b'previous output\n')
                (work/'left.s').write_text(original)
                original_main=(work/'main.s').read_text()
                (work/'main.s').write_text(original_main.replace('left.own() + right.own()', 'left.local_port(true) + right.own()'))
                artifact.write_bytes(b'previous output\n')
                with self.subTest(compiler=compiler.name,variant='qualified-wrong-type'):
                    rejected=subprocess.run(command,cwd=ROOT,capture_output=True,timeout=60)
                    self.assertNotEqual(rejected.returncode,0,rejected.stderr)
                    self.assertEqual(artifact.read_bytes(),b'previous output\n')
                (work/'main.s').write_text(original_main)

    def test_tuple_owner_in_borrowed_body_preserves_transparent_not_lexical_scope(self):
        valid = (ROOT / 'test/http/seed-borrow-repro/reduced/main.s').read_text()
        variants = {
            'valid': valid,
            'expired': valid.replace('    local,error := create()\n    return reset(local*)',
                                     '    { local,error := create() }\n    return reset(local*)'),
            'wrong': valid.replace('struct cell { int value }', 'struct cell { int value }\nstruct Other { int value }')
                          .replace('    local,error := create()', '    local := Other { value: 1 }'),
            'alias': valid.replace('func nested(', 'func pair(cell* left, cell* right) int { return left.value }\nfunc nested(')
                          .replace('return reset(local*)', 'return pair(local*,local*)'),
        }
        for compiler in (ROOT / 'bin/s_seed', ROOT / 'bin/s_compiler'):
            seed = compiler.name == 's_seed'
            with tempfile.TemporaryDirectory() as directory:
                work = Path(directory)
                for name, text in variants.items():
                    with self.subTest(compiler=compiler.name, variant=name):
                        source, artifact, binary = work/'main.s', work/'main.ir', work/'program'
                        source.write_text(text)
                        artifact.write_bytes(b'previous output\n')
                        build = subprocess.run([str(compiler), '--compile-native-unit' if seed else '--compile-unit',
                                                str(artifact), str(ROOT/'src/result/result.s'), str(source)],
                                               cwd=ROOT, capture_output=True, timeout=60)
                        if name != 'valid':
                            self.assertNotEqual(build.returncode, 0, build.stderr)
                            self.assertEqual(artifact.read_bytes(), b'previous output\n')
                            continue
                        self.assertEqual(build.returncode, 0, build.stderr.decode(errors='replace'))
                        emit = subprocess.run([str(compiler), '--emit-standalone-amd64' if seed else '--emit-bin',
                                               str(artifact), str(binary)], cwd=ROOT,
                                              env=os.environ|{'S_SOURCE_ROOT':str(ROOT)}, capture_output=True, timeout=60)
                        self.assertEqual(emit.returncode, 0, emit.stderr)
                        self.assertEqual(subprocess.run([str(binary)], timeout=10).returncode, 0)

    def test_specialized_method_candidate_survives_tuple_producer_rewalk(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            source = work / 'main.s'
            source.write_text('package main\nimport ("std.option"; "std.result")\nfunc present[t](t value) (int,option[t]) { return 0,option.some(value) }\nfunc identity[t](t value) (t,int) { return value,0 }\nfunc process[t](t value) t {\n    ignored,item := present(value)\n    moved,error := identity(item.unwrap())\n    return moved\n}\nfunc main() int { return process(42) }\n')
            intermediate, binary = work / 'main.ir', work / 'program'
            for command in ([str(ROOT / 'bin/s_seed'), '--compile-native-unit', str(intermediate), str(source),
                             str(ROOT / 'src/option/option.s'), str(ROOT / 'src/result/result.s')],
                            [str(ROOT / 'bin/s_seed'), '--emit-standalone-amd64', str(intermediate), str(binary)]):
                result = subprocess.run(command, cwd=ROOT, env=os.environ | {'S_SOURCE_ROOT': str(ROOT)},
                                        capture_output=True, timeout=60)
                self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(subprocess.run([str(binary)], timeout=10).returncode, 42)

    def test_qualified_source_functions_override_legacy_runtime_leaf_aliases(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            api = work / 'api.s'
            api.write_text('package api\nstruct Value { int number }\n'
                           'func slice(string text, int start, int end) Value { return Value { number: 40 } }\n'
                           'func byte_at(string text, int index) int { return 2 }\n')
            source = work / 'main.s'
            source.write_text('package main\nimport "api"\nfunc main() int { '
                              'value := api.slice("x",0,1); return value.number + api.byte_at("x",0) }\n')
            intermediate, binary = work / 'main.ir', work / 'program'
            for command in ([str(ROOT / 'bin/s_seed'), '--compile-native-unit', str(intermediate), str(api), str(source)],
                            [str(ROOT / 'bin/s_seed'), '--emit-standalone-amd64', str(intermediate), str(binary)]):
                result = subprocess.run(command, cwd=ROOT, env=os.environ | {'S_SOURCE_ROOT': str(ROOT)},
                                        capture_output=True, timeout=60)
                self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(binary)], capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 42, result.stderr)

    def test_imported_tuple_owner_and_rejected_wrong_or_expired_owner(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            api = work / 'api.s'
            api.write_text('''package api
struct Value { int number }
func create_value() (Value,int) { return Value { number: 1 }, 0 }
func reset(Value* value) int { value.number = 42; return 0 }
''')
            for name, body, wanted in (
                ('valid', 'value, error := api.create_value(); api.reset(value*); return value.number', 42),
                ('wrong', 'value := Other { number: 1 }; api.reset(value*); return 0', None),
                ('scope', '{ value, error := api.create_value() }; api.reset(value*); return 0', None),
            ):
                with self.subTest(name=name):
                    source = work / 'main.s'
                    source.write_text('package main\nimport "api"\nstruct Other { int number }\nfunc main() int { ' + body + ' }\n')
                    intermediate, binary = work / (name + '.ir'), work / name
                    intermediate.write_bytes(b'previous output\n')
                    result = subprocess.run([str(ROOT / 'bin/s_seed'), '--compile-native-unit', str(intermediate),
                                             str(ROOT / 'src/result/result.s'), str(api), str(source)],
                                            capture_output=True, timeout=60)
                    if wanted is None:
                        self.assertNotEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(intermediate.read_bytes(), b'previous output\n')
                        continue
                    self.assertEqual(result.returncode, 0, result.stderr)
                    result = subprocess.run([str(ROOT / 'bin/s_seed'), '--emit-standalone-amd64',
                                             str(intermediate), str(binary)], cwd=ROOT,
                                            env=os.environ | {'S_SOURCE_ROOT': str(ROOT)}, capture_output=True, timeout=60)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    result = subprocess.run([str(binary)], capture_output=True, timeout=10)
                    self.assertEqual(result.returncode, wanted, result.stderr)


if __name__ == '__main__':
    unittest.main()
