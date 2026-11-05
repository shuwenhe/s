"""Native ANSI bytes, real PTY dimensions, session restoration and safe writes."""
from pathlib import Path
import errno
import fcntl
import os
import pty
import struct
import subprocess
import tempfile
import termios
import unittest

ROOT = Path(__file__).resolve().parents[2]
COMPILER = Path(os.environ.get('S_TEST_COMPILER', ROOT / 'bin/s_compiler')).resolve()
ANSI = b'\x1b[2J\x1b[H\x1b[3;5H\x1b[1;31;44mS\x1b[0m'


class NativeTerminalTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='s-terminal-')
        cls.work = Path(cls.temporary.name)
        cls.binary = cls.work / 'terminal'
        sources = [ROOT / 'src/std/terminal.s', ROOT / 'src/result/result.s',
                   ROOT / 'src/prelude/prelude.s', ROOT / 'test/stdlib-native/terminal.s']
        cls.sources = sources
        result = subprocess.run([str(COMPILER), '--compile-unit', str(cls.work / 'main.sasm'), *map(str, sources)],
                                capture_output=True, timeout=60)
        if result.returncode:
            raise AssertionError(result.stderr)
        result = subprocess.run([str(COMPILER), '--emit-bin', str(cls.work / 'main.sasm'), str(cls.binary)],
                                capture_output=True, timeout=30)
        if result.returncode:
            raise AssertionError(result.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def test_ansi_and_buffer_boundaries(self):
        result = subprocess.run([str(self.binary)], capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, ANSI)

    def tty(self, mode, binary=None):
        master, slave = pty.openpty()
        try:
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 37, 91, 0, 0))
            result = subprocess.run([str(binary or self.binary), mode], stdin=slave, stdout=slave, stderr=subprocess.PIPE, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            os.set_blocking(master, False)
            output = bytearray()
            while True:
                try:
                    data = os.read(master, 4096)
                    if not data:
                        break
                    output.extend(data)
                except BlockingIOError:
                    break
            return bytes(output)
        finally:
            os.close(master)
            os.close(slave)

    def test_real_terminal_dimensions(self):
        self.assertEqual(self.tty('dimensions').replace(b'\r\n', b'\n'), b'37x91\n')

    def test_explicit_and_normal_exit_restore_alternate_screen_and_cursor(self):
        for mode in ('session', 'explicit'):
            with self.subTest(mode=mode):
                output = self.tty(mode)
                self.assertIn(b'\x1b[?1049h', output)
                self.assertIn(b'\x1b[?25l', output)
                self.assertTrue(output.endswith(b'\x1b[?25h\x1b[?1049l'), output)
                self.assertEqual(output.count(b'\x1b[?1049l'), 1)

    def test_non_terminal_initialization_fails_without_ansi_output(self):
        result = subprocess.run([str(self.binary), 'not-tty'], capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, b'')

    def test_write_eintr_and_error_preserve_buffer(self):
        for injection, mode, output in (('EINTR', 'buffer', ANSI), ('EIO', 'io-error', b'')):
            with self.subTest(injection=injection):
                result = subprocess.run(['strace', '-qq', '-o', str(self.work / (injection + '.trace')),
                                         '-e', 'trace=write', '-e', 'inject=write:error=' + injection + ':when=1',
                                         str(self.binary), mode], capture_output=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, output)

    def test_closed_pipe_returns_epipe_instead_of_terminating(self):
        read_fd, write_fd = os.pipe()
        os.close(read_fd)
        try:
            result = subprocess.run([str(self.binary), 'closed-pipe'], stdout=write_fd, stderr=subprocess.PIPE, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
        finally:
            os.close(write_fd)

    def test_seed_standalone_terminal_bytes_and_normal_exit_cleanup(self):
        intermediate, binary = self.work / 'seed.ir', self.work / 'seed-terminal'
        result = subprocess.run([str(ROOT / 'bin/s_seed'), '--compile-native-unit', str(intermediate), *map(str, self.sources)],
                                capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = subprocess.run([str(ROOT / 'bin/s_seed'), '--emit-standalone-amd64', str(intermediate), str(binary)],
                                cwd=ROOT, env=os.environ | {'S_SOURCE_ROOT': str(ROOT)}, capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = subprocess.run([str(binary)], capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, ANSI)
        self.assertTrue(self.tty('session', binary).endswith(b'\x1b[?25h\x1b[?1049l'))


if __name__ == '__main__':
    unittest.main()
