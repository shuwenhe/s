"""Real S ELF timing, CPU consumption, errno and EINTR acceptance."""
from pathlib import Path
import json
import os
import resource
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
COMPILER = Path(os.environ.get('S_TEST_COMPILER', ROOT / 'bin/s_compiler')).resolve()


class NativeTimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='s-time-native-')
        cls.work = Path(cls.temporary.name)
        cls.binary = cls.work / 'time'
        cls.build(cls.binary)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    @classmethod
    def build(cls, binary, seed=False):
        sources = [ROOT / 'src/std/time.s', ROOT / 'src/result/result.s',
                   ROOT / 'src/prelude/prelude.s', ROOT / 'test/stdlib-native/time.s']
        intermediate = binary.with_suffix('.ir' if seed else '.sasm')
        producer = ROOT / 'bin/s_seed' if seed else COMPILER
        command = [str(producer), '--compile-native-unit' if seed else '--compile-unit', str(intermediate), *map(str, sources)]
        result = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=60)
        if result.returncode:
            raise AssertionError((command, result.returncode, result.stderr.decode()))
        result = subprocess.run([str(producer), '--emit-standalone-amd64' if seed else '--emit-bin',
                                 str(intermediate), str(binary)], cwd=ROOT, capture_output=True,
                                env=os.environ | {'S_SOURCE_ROOT': str(ROOT)}, timeout=60)
        if result.returncode:
            raise AssertionError((result.returncode, result.stderr.decode()))

    def measured(self, command):
        before = resource.getrusage(resource.RUSAGE_CHILDREN)
        wall_before = time.time_ns()
        started = time.monotonic()
        result = subprocess.run(list(map(str, command)), capture_output=True, timeout=10)
        elapsed = time.monotonic() - started
        after = resource.getrusage(resource.RUSAGE_CHILDREN)
        cpu = after.ru_utime + after.ru_stime - before.ru_utime - before.ru_stime
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        self.assertEqual(len(lines), 2, result.stdout)
        clock, reported = map(int, lines)
        self.assertGreaterEqual(clock, wall_before - 1_000_000_000)
        self.assertLessEqual(clock, time.time_ns() + 1_000_000_000)
        self.assertGreaterEqual(reported, 200_000_000)
        self.assertGreaterEqual(elapsed, 0.19)
        self.assertLess(cpu, 0.08, 'sleep must block rather than consume CPU')
        print(json.dumps({'command': list(map(str, command)), 'elapsed_seconds': elapsed, 'cpu_seconds': cpu,
                          'reported_ns': reported}), flush=True)

    def test_sleep_clocks_duration_timers_boundaries_and_cpu(self):
        self.measured([self.binary, '0'])

    def test_seed_standalone_uses_identical_real_os_contract(self):
        self.measured([self.seed_binary(), '0'])

    def seed_binary(self):
        binary = self.work / 'seed-time'
        if not binary.exists():
            self.build(binary, seed=True)
        return binary

    def test_eintr_restarts_remaining_sleep(self):
        for binary in (self.binary, self.seed_binary()):
            trace = self.work / (binary.name + '-eintr.trace')
            self.measured(['strace', '-qq', '-o', trace, '-e', 'trace=nanosleep', '-e',
                           'inject=nanosleep:error=EINTR:when=1', binary, '0'])
            self.assertIn('EINTR', trace.read_text())

    def test_kernel_errors_are_propagated(self):
        for binary in (self.binary, self.seed_binary()):
          for syscall, mode in (('clock_gettime', '1'), ('nanosleep', '2'), ('clock_gettime', '5')):
            with self.subTest(binary=binary.name, syscall=syscall, mode=mode):
                result = subprocess.run(['strace', '-qq', '-o', str(self.work / (syscall + '.trace')),
                                         '-e', 'trace=' + syscall, '-e', 'inject=' + syscall + ':error=EIO:when=1',
                                         str(binary), mode], capture_output=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_exact_int64_duration_boundary_reaches_os_without_wrapping(self):
        for binary in (self.binary, self.seed_binary()):
          for mode in ('3', '4'):
            with self.subTest(binary=binary.name, mode=mode):
                result = subprocess.run(['strace', '-qq', '-o', str(self.work / ('maximum-' + mode + '.trace')),
                                         '-e', 'trace=nanosleep', '-e', 'inject=nanosleep:retval=0:when=1',
                                         str(binary), mode], capture_output=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('tv_sec=9223372036, tv_nsec=854775807',
                              (self.work / ('maximum-' + mode + '.trace')).read_text())

    def test_real_repeated_signals_resume_remaining_time(self):
        combined = self.work / 'combined.s'
        sources = [ROOT / 'src/std/time.s', ROOT / 'src/result/result.s',
                   ROOT / 'src/prelude/prelude.s', ROOT / 'test/stdlib-native/time.s']
        combined.write_text('\n'.join(p.read_text() for p in sources))
        obj = self.work / 'interrupted.o'
        result = subprocess.run([str(COMPILER), '--emit-native-object', str(combined), str(obj)],
                                capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        runner = self.work / 'interrupt.c'
        runner.write_text('''#define _POSIX_C_SOURCE 200809L
#include <signal.h>
#include <sys/time.h>
extern long s_native_entry(void);
static volatile sig_atomic_t ticks;
static void interrupt_sleep(int signal) { (void)signal; ++ticks; }
int main(void) {
    struct sigaction action = {0};
    action.sa_handler = interrupt_sleep;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGALRM, &action, 0)) return 41;
    struct itimerval alarm = {{0, 50000}, {0, 50000}};
    if (setitimer(ITIMER_REAL, &alarm, 0)) return 42;
    long result = s_native_entry();
    struct itimerval disabled = {{0, 0}, {0, 0}};
    if (setitimer(ITIMER_REAL, &disabled, 0)) return 43;
    if (ticks < 2) return 44;
    return (int)result;
}
''')
        binary = self.work / 'real-interrupt'
        result = subprocess.run([os.environ.get('CC', 'cc'), '-std=c11', '-Wall', '-Wextra', '-Werror',
                                 str(runner), str(obj), '-o', str(binary)], capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        # Repeated 50ms signals would prevent a full 160ms restart from ever
        # completing. Only consuming each kernel remainder can finish.
        self.measured([binary])


if __name__ == '__main__':
    unittest.main()
