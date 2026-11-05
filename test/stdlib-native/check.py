"""Execute actual shipped option/result/prelude sources through the native ABI."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
COMPILER = Path(os.environ.get('S_TEST_COMPILER', ROOT / 'bin/s_compiler')).resolve()
SOURCE = '''package main
import ("std.option"; "std.result"; "std.prelude")
func present() option[int] { return option.some(41) }
func absent() option[int] { return option.none }
func success() result[int,string] { return result.ok(42) }
func failure() result[int,string] { return result.err("failure") }
func main(int input) int {
    value := present()
    missing := absent()
    if !value.is_some() || value.is_none() { return 1 }
    if !missing.is_none() || missing.is_some() { return 2 }
    if value.unwrap_or(0) != 41 || missing.unwrap_or(42) != 42 { return 3 }
    if value.unwrap() != 41 { return 4 }
    good := success()
    bad := failure()
    if !good.is_ok() || good.is_err() || !bad.is_err() || bad.is_ok() { return 5 }
    if good.unwrap() != 42 || bad.unwrap_err() != "failure" { return 6 }
    if std.prelude.to_string(-9223372036854775808) != "-9223372036854775808" { return 7 }
    if std.prelude.len("abc") != 3 || std.prelude.char_at("abc", 1) != "b" { return 8 }
    if input == 1 { return missing.unwrap() }
    if input == 2 { return bad.unwrap() }
    if input == 3 { ignored := good.unwrap_err(); return 9 }
    return 0
}
'''


class NativeLibraryTests(unittest.TestCase):
    def test_shipped_error_and_prelude_apis_and_checked_unwrap(self):
        with tempfile.TemporaryDirectory(prefix='s-stdlib-native-') as directory:
            work = Path(directory)
            source = work / 'main.s'
            source.write_text(SOURCE)
            assembly, binary = work / 'main.sasm', work / 'main'
            result = subprocess.run([str(COMPILER), '--compile-unit', str(assembly),
                                     str(ROOT / 'src/option/option.s'), str(ROOT / 'src/result/result.s'),
                                     str(ROOT / 'src/prelude/prelude.s'), str(source)],
                                    capture_output=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(COMPILER), '--emit-bin', str(assembly), str(binary)],
                                    capture_output=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            for argument, wanted in (('0', 0), ('1', 101), ('2', 101), ('3', 101)):
                with self.subTest(argument=argument):
                    result = subprocess.run([str(binary), argument], capture_output=True, timeout=10)
                    self.assertEqual(result.returncode, wanted, result.stderr)


if __name__ == '__main__':
    unittest.main()
