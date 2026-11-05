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
import re

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

    def tty(self, mode, binary=None, wanted=0):
        master, slave = pty.openpty()
        try:
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 37, 91, 0, 0))
            result = subprocess.run([str(binary or self.binary), mode], stdin=slave, stdout=slave, stderr=subprocess.PIPE, timeout=10)
            self.assertEqual(result.returncode, wanted, result.stderr)
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

    def test_normal_cleanup_preserves_nonzero_exit_status(self):
        self.assertTrue(self.tty('session-status', wanted=37).endswith(b'\x1b[?25h\x1b[?1049l'))

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

    def test_partial_nonblocking_write_retains_only_unsent_suffix(self):
        read_fd, write_fd = os.pipe()
        fcntl.fcntl(write_fd, fcntl.F_SETPIPE_SZ, 4096)
        os.set_blocking(write_fd, False)
        try:
            result = subprocess.run([str(self.binary), 'partial'], stdout=write_fd, stderr=subprocess.PIPE, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            os.close(write_fd)
            write_fd = -1
            data = bytearray()
            while True:
                chunk = os.read(read_fd, 65536)
                if not chunk:
                    break
                data.extend(chunk)
            consumed = int(result.stderr.strip())
            self.assertEqual(len(data), consumed)
            self.assertGreater(consumed, 0)
            self.assertLess(consumed, 32768)
            self.assertEqual(data, b'x' * consumed)
        finally:
            os.close(read_fd)
            if write_fd >= 0:
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
        self.assertTrue(self.tty('session-status', binary, wanted=37).endswith(b'\x1b[?25h\x1b[?1049l'))

    def test_epipe_preserves_signal_mask_handler_and_preexisting_pending_signal(self):
        source = self.work / 'signal-state.s'
        source.write_text('\n'.join(p.read_text() for p in self.sources[:-1]) + '''
package main
import "std.terminal"
func main() int {
    output, error := std.terminal.new_buffer(1, 16)
    if std.terminal.buffer_append(output*, "data").code != 0 { return 1 }
    error = std.terminal.flush(output*)
    if error.code != 32 || output.pending != "data" { return 2 }
    return 0
}
''')
        obj = self.work / 'signal-state.o'
        result = subprocess.run([str(COMPILER), '--emit-native-object', str(source), str(obj)], capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        runner = self.work / 'signal-state.c'
        runner.write_text('''#define _POSIX_C_SOURCE 200809L
#include <signal.h>
#include <unistd.h>
extern long s_native_entry(void);
static volatile sig_atomic_t calls;
static void handler(int number) { (void)number; ++calls; }
int main(int argc, char **argv) {
    (void)argv;
    int descriptors[2];
    if (pipe(descriptors)) return 41;
    close(descriptors[0]);
    if (dup2(descriptors[1], 1) < 0) return 42;
    close(descriptors[1]);
    struct sigaction action = {0};
    action.sa_handler = handler;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGPIPE, &action, 0)) return 43;
    sigset_t mask, observed, pending;
    sigemptyset(&mask);
    sigaddset(&mask, SIGUSR1);
    if (argc > 1) sigaddset(&mask, SIGPIPE);
    if (sigprocmask(SIG_SETMASK, &mask, 0)) return 44;
    if (argc > 1 && raise(SIGPIPE)) return 45;
    if (s_native_entry() != 0) return 46;
    if (sigprocmask(SIG_SETMASK, 0, &observed)) return 47;
    if (sigismember(&observed, SIGUSR1) != 1 || sigismember(&observed, SIGPIPE) != (argc > 1)) return 48;
    if (sigpending(&pending)) return 49;
    if (sigismember(&pending, SIGPIPE) != (argc > 1) || calls) return 50;
    if (argc == 1) {
        if (raise(SIGPIPE) || calls != 1) return 51;
    }
    return 0;
}
''')
        binary = self.work / 'signal-state'
        result = subprocess.run([os.environ.get('CC', 'cc'), '-std=c11', '-Wall', '-Wextra', '-Werror',
                                 str(runner), str(obj), '-o', str(binary)], capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        for args in ([], ['pending']):
            result = subprocess.run([str(binary), *args], capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_seed_write_allocation_failure_is_enomem_not_null_copy(self):
        runtime = (ROOT / 'src/runtime/selfhost_linux_amd64.S').read_text()
        macro = re.search(r'\.macro S_UNTAG register\n.*?\.endm', runtime, re.S)[0]
        start = runtime.index('.global s_std_write_value')
        stop = runtime.index('.global ', start + len('.global s_std_write_value'))
        assembly = self.work / 'seed-write-adapter.s'
        assembly.write_text(macro + '\n.text\n' + runtime[start:stop] + '\n.section .note.GNU-stack,"",@progbits\n')
        runner = self.work / 'allocation-failure.c'
        runner.write_text('''#include <errno.h>
#include <stddef.h>
extern long s_std_write_value(long, const long *, long);
void *s_alloc(long count) { (void)count; return NULL; }
long s_value_len(const long *value) { return value[1] * 2 + 1; }
long s_string_byte_raw(const long *value, long index) { (void)value; (void)index; return 97; }
long s_integer_pack(long value) { return value * 2 + 1; }
long s_os_write(long fd, const void *buffer, long count) { (void)fd; (void)buffer; (void)count; return -EIO; }
int main(void) {
    const long value[] = {2, 8, 0x6161616161616161};
    long result = s_std_write_value(3, value, 1);
    return result == -ENOMEM * 2 + 1 && value[1] == 8 ? 0 : 1;
}
''')
        binary = self.work / 'allocation-failure'
        result = subprocess.run([os.environ.get('CC', 'cc'), '-std=c11', '-Wall', '-Wextra', '-Werror',
                                 str(runner), str(assembly), '-o', str(binary)], capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = subprocess.run([str(binary)], capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
