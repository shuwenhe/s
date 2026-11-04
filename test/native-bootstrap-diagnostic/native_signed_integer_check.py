#!/usr/bin/env python3
"""Validate signed literal limits and negative switch patterns through native MIR."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SEED = os.environ.get('S_TEST_SEED') == '1'
COMPILER = Path(os.environ.get('S_TEST_COMPILER', str(ROOT / ('bin/s_seed' if SEED else 'bin/s_compiler')))).resolve()


class SignedIntegerTests(unittest.TestCase):
    def test_valid_signed_literals_execute(self):
        bodies = {
            'maximum': 'value := 9223372036854775807; if value - 1 == 9223372036854775806 { return 42 }\nreturn 1',
            'minimum_precedence': 'if -9223372036854775808 + 1 == -9223372036854775807 { return 42 }\nreturn 1',
            'minimum': 'value := -9223372036854775808; if value + 1 == -9223372036854775807 { return 42 }\nreturn 1',
            'minimum_leading_zero': 'value := -0009223372036854775808; if value + 1 == -9223372036854775807 { return 42 }\nreturn 1',
            'negative_pattern': 'return switch -1 { -1: 42, _: 1 }',
            'minimum_pattern': 'return switch (-9223372036854775807 - 1) { -9223372036854775808: 42, _: 1 }',
            'nested_negation': 'value := -(-9223372036854775808); if value + 1 == -9223372036854775807 { return 42 }\nreturn 1',
        }
        if SEED:
            bodies.update({
                'hex_maximum': 'if 0x7fffffffffffffff == 9223372036854775807 { return 42 }\nreturn 1',
                'hex_minimum': 'if -0x8000000000000000 + 1 == -9223372036854775807 { return 42 }\nreturn 1',
                'enum_tag_maximum': 'if to_string(Boundary.maximum) == "9223372036854775807" { return 42 }\nreturn 1',
            })
        for name, body in bodies.items():
            with self.subTest(case=name), tempfile.TemporaryDirectory(prefix='s-signed-literal-') as directory:
                work = Path(directory)
                source, assembly, binary = work / 'main.s', work / 'main.sasm', work / 'main'
                prefix = 'package main\n'
                if SEED:
                    prefix += 'enum Boundary { maximum = 9223372036854775807 }\n'
                source.write_text(prefix + 'func main() int {\n' + body + '\n}\n')
                result = subprocess.run([str(COMPILER), '--compile-unit', str(assembly), str(source)], capture_output=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stderr.decode())
                subprocess.run([str(COMPILER), '--emit-standalone-amd64' if SEED else '--emit-bin', str(assembly), str(binary)], check=True, timeout=30,
                               env=dict(os.environ, S_SOURCE_ROOT=str(ROOT)))
                result = subprocess.run([str(binary)], capture_output=True, timeout=5)
                self.assertEqual(result.returncode, 42, (name, result.stderr))

    def test_out_of_range_literals_preserve_output(self):
        for spelling in ('9223372036854775808', '0009223372036854775808', '-9223372036854775809', '9999999999999999999999999999999999999999',
                         'switch 0 { -9223372036854775809: 42, _: 1 }'):
            with self.subTest(spelling=spelling), tempfile.TemporaryDirectory(prefix='s-signed-reject-') as directory:
                work = Path(directory)
                source, assembly = work / 'main.s', work / 'main.sasm'
                source.write_text('package main\nfunc main() int { return ' + spelling + ' }\n')
                assembly.write_bytes(b'preserve accepted artifact\n')
                result = subprocess.run([str(COMPILER), '--compile-unit', str(assembly), str(source)], capture_output=True, timeout=30)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(b'integer literal exceeds int64', result.stderr)
                self.assertEqual(assembly.read_bytes(), b'preserve accepted artifact\n')

    def test_array_literal_overflow_preserves_output(self):
        with tempfile.TemporaryDirectory(prefix='s-array-integer-reject-') as directory:
            work = Path(directory)
            source, assembly = work / 'main.s', work / 'main.sasm'
            source.write_text('package main\nfunc main() int { values := int[]{9223372036854775808}; return values[0] }\n')
            assembly.write_bytes(b'preserve accepted artifact\n')
            result = subprocess.run([str(COMPILER), '--compile-unit', str(assembly), str(source)], capture_output=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b'integer literal exceeds int64', result.stderr)
            self.assertEqual(assembly.read_bytes(), b'preserve accepted artifact\n')

    def test_enum_discriminant_overflow_preserves_output(self):
        for spelling in ('9223372036854775808', '9999999999999999999999999999999999999999'):
            with self.subTest(spelling=spelling), tempfile.TemporaryDirectory(prefix='s-enum-integer-reject-') as directory:
                work = Path(directory)
                source, assembly = work / 'main.s', work / 'main.sasm'
                source.write_text('package main\nenum Tag { invalid = ' + spelling + ' }\nfunc main() int { return 42 }\n')
                assembly.write_bytes(b'preserve accepted artifact\n')
                result = subprocess.run([str(COMPILER), '--compile-unit', str(assembly), str(source)], capture_output=True, timeout=30)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(b'enum', result.stderr)
                self.assertEqual(assembly.read_bytes(), b'preserve accepted artifact\n')


if __name__ == '__main__':
    unittest.main(verbosity=2)
