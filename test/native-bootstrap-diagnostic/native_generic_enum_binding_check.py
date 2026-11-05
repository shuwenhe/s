"""Enum constructor identities must become concrete inside generic functions."""
from pathlib import Path
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[2]


class GenericEnumBindingTests(unittest.TestCase):
    def test_generic_option_some_and_none_are_rewritten_to_concrete_enum(self):
        with tempfile.TemporaryDirectory(prefix='s-generic-option-') as directory:
            work = Path(directory)
            source = work / 'main.s'
            source.write_text('''package main
import "std.option"
func first[t](t[] values) option[t] {
    if len(values) == 0 { return option[t].none }
    return option.some(values[0])
}
func main() int {
    present := first(int[]{42})
    absent := first(int[]())
    if !absent.is_none() { return 1 }
    return present.unwrap_or(0)
}
''')
            assembly, binary = work / 'main.sasm', work / 'program'
            result = subprocess.run([str(ROOT / 'bin/s_compiler'), '--compile-unit', str(assembly),
                                     str(ROOT / 'src/option/option.s'), str(source)], capture_output=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(ROOT / 'bin/s_compiler'), '--emit-bin', str(assembly), str(binary)], capture_output=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(subprocess.run([str(binary)], timeout=5).returncode, 42)


if __name__ == '__main__':
    unittest.main()
