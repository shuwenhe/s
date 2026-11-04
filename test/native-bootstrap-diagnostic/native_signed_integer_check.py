#!/usr/bin/env python3
"""Validate signed literal limits and negative switch patterns through native MIR."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
COMPILER = ROOT / 'bin/s_compiler'


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
        for name, body in bodies.items():
            with self.subTest(case=name), tempfile.TemporaryDirectory(prefix='s-signed-literal-') as directory:
                work = Path(directory)
                source, assembly, binary = work / 'main.s', work / 'main.sasm', work / 'main'
                source.write_text('package main\nfunc main() int {\n' + body + '\n}\n')
                result = subprocess.run([str(COMPILER), '--compile-unit', str(assembly), str(source)], capture_output=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stderr.decode())
                subprocess.run([str(COMPILER), '--emit-bin', str(assembly), str(binary)], check=True, timeout=30)
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


if __name__ == '__main__':
    unittest.main(verbosity=2)
