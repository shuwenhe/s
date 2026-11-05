"""Actual imported native S Snake, deterministic rules and PTY lifecycle."""
from pathlib import Path
import fcntl
import os
import pty
import resource
import re
import select
import struct
import subprocess
import tempfile
import termios
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]


class NativeSnakeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='s-snake-')
        cls.binary = Path(cls.temp.name) / 'snake'
        result = subprocess.run(['sh', str(ROOT / 'misc/scripts/s-driver.sh'), 'build',
                                 str(ROOT / 'examples/snake/main.s'), '-o', str(cls.binary)],
                                cwd=ROOT, capture_output=True, timeout=90)
        if result.returncode:
            raise AssertionError(result.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_deterministic_rules(self):
        result = subprocess.run([str(self.binary), '--self-test'], capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, b'snake rules: PASS\n')

    def test_requires_terminal(self):
        result = subprocess.run([str(self.binary)], input=b'', capture_output=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(b'\x1b[?1049h', result.stdout)

    def test_play_frames_and_quit_restore_terminal_without_busy_wait(self):
        master, slave = pty.openpty()
        original = termios.tcgetattr(slave)
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
        before = resource.getrusage(resource.RUSAGE_CHILDREN)
        process = subprocess.Popen([str(self.binary)], stdin=slave, stdout=slave, stderr=subprocess.PIPE)
        output = bytearray()
        try:
            deadline = time.monotonic() + 3
            while b'WASD' not in output and time.monotonic() < deadline:
                if select.select([master], [], [], 0.1)[0]:
                    output.extend(os.read(master, 16384))
            self.assertIn(b'WASD', output)
            self.assertFalse(termios.tcgetattr(slave)[3] & termios.ICANON)
            heads = lambda: re.findall(rb'\x1b\[(\d+);(\d+)HO', output)
            deadline = time.monotonic() + 2
            while len(heads()) < 3 and time.monotonic() < deadline:
                if select.select([master], [], [], 0.1)[0]:
                    output.extend(os.read(master, 16384))
            positions = heads()
            self.assertGreaterEqual(len(positions), 3, 'timed simulation must advance the head')
            self.assertEqual(positions[:3], [(b'8', b'8'), (b'8', b'9'), (b'8', b'10')])
            previous = positions[-1]
            count = len(positions)
            os.write(master, b'\x1b[B')
            deadline = time.monotonic() + 1
            while len(heads()) == count and time.monotonic() < deadline:
                if select.select([master], [], [], 0.1)[0]:
                    output.extend(os.read(master, 16384))
            positions = heads()
            self.assertGreater(len(positions), count, 'arrow must affect a subsequent simulation tick')
            self.assertEqual(positions[count], (str(int(previous[0]) + 1).encode(), previous[1]))
            os.write(master, b'q')
            _, error = process.communicate(timeout=5)
            while select.select([master], [], [], 0)[0]:
                output.extend(os.read(master, 16384))
            self.assertEqual(process.returncode, 0, error)
            self.assertEqual(termios.tcgetattr(slave), original)
            self.assertEqual(output.count(b'\x1b[2J'), 1, 'frames must update dirty cells, not clear the screen')
            self.assertIn(b'\x1b[?25h\x1b[?1049l', output)
            after = resource.getrusage(resource.RUSAGE_CHILDREN)
            self.assertLess(after.ru_utime + after.ru_stime - before.ru_utime - before.ru_stime, 0.15)
        finally:
            if process.poll() is None:
                process.kill()
            process.wait()
            termios.tcsetattr(slave, termios.TCSANOW, original)
            os.close(master)
            os.close(slave)


if __name__ == '__main__':
    unittest.main()
