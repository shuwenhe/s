"""Native keyboard parsing, blocking/polling, raw-mode and PTY restoration."""
from pathlib import Path
import os
import pty
import resource
import select
import subprocess
import tempfile
import termios
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
COMPILER = Path(os.environ.get('S_TEST_COMPILER', ROOT / 'bin/s_compiler')).resolve()


class NativeInputTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='s-input-native-')
        cls.work = Path(cls.temporary.name)
        cls.binary = cls.work / 'input'
        sources = [ROOT / 'src/std/input.s', ROOT / 'src/result/result.s',
                   ROOT / 'src/prelude/prelude.s', ROOT / 'test/stdlib-native/input.s']
        cls.sources = sources
        result = subprocess.run([str(COMPILER), '--compile-unit', str(cls.work / 'main.sasm'), *map(str, sources)],
                                capture_output=True, timeout=60)
        if result.returncode:
            raise AssertionError(result.stderr)
        result = subprocess.run([str(COMPILER), '--emit-bin', str(cls.work / 'main.sasm'), str(cls.binary)], capture_output=True, timeout=30)
        if result.returncode:
            raise AssertionError(result.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def test_arrows_wasd_escape_binary_bytes_and_eof(self):
        result = subprocess.run([str(self.binary)], input=b'\x1b[A\x1b[B\x1b[C\x1b[Dwasdq\x00\x1b', capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), [b'up:65', b'down:66', b'right:67', b'left:68',
                         b'up:119', b'left:97', b'down:115', b'right:100', b'key:113', b'key:0', b'escape:27', b'eof:0'])

    def test_fragmented_escape_sequence_and_standalone_escape_timeout(self):
        process = subprocess.Popen([str(self.binary)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            for fragment in (b'\x1b', b'[', b'A'):
                process.stdin.write(fragment)
                process.stdin.flush()
                time.sleep(0.003)
            self.assertTrue(select.select([process.stdout], [], [], 1)[0])
            self.assertEqual(process.stdout.readline(), b'up:65\n')
            process.stdin.write(b'\x1b')
            process.stdin.flush()
            self.assertTrue(select.select([process.stdout], [], [], 1)[0])
            self.assertEqual(process.stdout.readline(), b'escape:27\n')
            process.stdin.close()
            process.stdin = None
            output, error = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 0, error)
            self.assertEqual(output, b'eof:0\n')
        finally:
            if process.poll() is None:
                process.kill()
            process.wait()

    def test_nonblocking_no_data_returns_promptly(self):
        read_fd, write_fd = os.pipe()
        try:
            started = time.monotonic()
            result = subprocess.run([str(self.binary), 'nonblock'], stdin=read_fd, capture_output=True, timeout=2)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertLess(time.monotonic() - started, 0.5)
        finally:
            os.close(read_fd)
            os.close(write_fd)

    def test_raw_mode_requires_tty(self):
        result = subprocess.run([str(self.binary), 'notty'], input=b'', capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)

    def raw_session(self, mode, binary=None, inject=False):
        master, slave = pty.openpty()
        original = termios.tcgetattr(slave)
        command = [str(binary or self.binary), mode]
        if inject:
            command = ['strace', '-qq', '-o', str(self.work / 'read-error.trace'), '-e', 'trace=read',
                       '-e', 'inject=read:error=EIO:when=1', *command]
        before = resource.getrusage(resource.RUSAGE_CHILDREN)
        process = subprocess.Popen(command, stdin=slave, stdout=slave, stderr=subprocess.PIPE)
        try:
            output = bytearray()
            deadline = time.monotonic() + 3
            while b'READY' not in output and time.monotonic() < deadline:
                if select.select([master], [], [], 0.2)[0]:
                    output.extend(os.read(master, 4096))
            self.assertIn(b'READY', output)
            current = termios.tcgetattr(slave)
            self.assertFalse(current[3] & termios.ICANON)
            self.assertFalse(current[3] & termios.ECHO)
            time.sleep(0.2)
            os.write(master, b'q')
            _, error = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 0, error)
            after = resource.getrusage(resource.RUSAGE_CHILDREN)
            cpu = after.ru_utime + after.ru_stime - before.ru_utime - before.ru_stime
            self.assertLess(cpu, 0.08, 'blocking input must not spin')
            self.assertEqual(termios.tcgetattr(slave), original)
        finally:
            if process.poll() is None:
                process.kill()
            process.wait()
            termios.tcsetattr(slave, termios.TCSANOW, original)
            os.close(master)
            os.close(slave)

    def test_raw_mode_normal_and_explicit_exit_restore_exact_settings(self):
        for mode in ('raw-exit', 'raw-explicit'):
            with self.subTest(mode=mode):
                self.raw_session(mode)

    def test_handled_read_error_restores_terminal(self):
        self.raw_session('raw-error', inject=True)


if __name__ == '__main__':
    unittest.main()
