#!/usr/bin/env python3
"""Keep concrete enum payload assignability consistent with seed semantics."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SEED = ROOT / 'bin/s_seed'
CASES = {
    'int_to_float': 'enum number { item(float) }\nfunc probe() number { return number.item(1) }',
    'float_to_int': 'enum number { item(int) }\nfunc probe() number { return number.item(1.5) }',
    'int_to_any': 'enum boxed { item(any) }\nfunc probe() boxed { return boxed.item(1) }',
    'string_to_any': 'enum boxed { item(any) }\nfunc probe() boxed { return boxed.item("value") }',
    'generic_fixed_any': 'enum tagged[T] { item(any) }\nfunc probe() tagged[int] { return tagged[int].item(1) }',
    'generic_fixed_float': 'enum tagged[T] { item(float) }\nfunc probe() tagged[int] { return tagged[int].item(1) }',
    'any_to_any': 'enum boxed { item(any) }\nfunc probe(any value) boxed { return boxed.item(value) }',
}
with tempfile.TemporaryDirectory(prefix='s-enum-assign-') as directory:
    work = Path(directory)
    for name, declarations in CASES.items():
        source = work / (name + '.s')
        source.write_text('package main\n' + declarations + '\nfunc main() int { return 42 }\n')
        # General seed semantics is the existing assignment compatibility oracle.
        for mode in ('--compile-unit', '--compile-native-unit'):
            result = subprocess.run([str(SEED), mode, str(work / (name + mode + '.ir')), str(source)], capture_output=True, timeout=30)
            assert result.returncode == 0, (name, mode, result.stderr.decode())
    source = work / 'generic-invariant.s'
    source.write_text('package main\nenum number[T] { item(T) }\nfunc probe() number[float] { return number.item(1) }\nfunc main() int { return 42 }\n')
    for mode in ('--compile-unit', '--compile-native-unit'):
        output = work / ('generic' + mode + '.ir')
        output.write_bytes(b'preserve artifact\n')
        result = subprocess.run([str(SEED), mode, str(output), str(source)], capture_output=True, timeout=30)
        assert result.returncode != 0, ('generic identity widened', mode)
        assert output.read_bytes() == b'preserve artifact\n'
print('enum payload numeric conversions and concrete any: seed semantic/native IR compatibility: PASS')
print('float/any native executable representation remains separate P1 work')
