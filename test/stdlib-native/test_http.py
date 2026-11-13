"""Native S HTTP health slice: real loopback sockets, no mock HTTP server."""
from contextlib import contextmanager
from pathlib import Path
import json
import os
import select
import signal
import socket
import struct
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]


class NativeHTTPTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='s-http-')
        cls.work = Path(cls.temporary.name)
        compiler = Path(os.environ.get('S_HTTP_COMPILER', ROOT / 'bin/s_compiler')).resolve()
        seed = compiler.name == 's_seed'
        sources = [ROOT / 'src/std/tcp.s', ROOT / 'src/std/time.s',
                   ROOT / 'src/result/result.s', ROOT / 'src/prelude/prelude.s',
                   *sorted((ROOT / 'src/std/http').glob('*.s'))]
        try:
            for name in ('protocol', 'server'):
                artifact = cls.work / (name + '.sasm')
                binary = cls.work / name
                for command in (
                    [str(compiler), '--compile-native-unit' if seed else '--compile-unit',
                     str(artifact), *map(str, sources), str(ROOT / 'test/http' / (name + '.s'))],
                    [str(compiler), '--emit-standalone-amd64' if seed else '--emit-bin', str(artifact), str(binary)],
                ):
                    result = subprocess.run(command, cwd=ROOT, capture_output=True,
                                            env=os.environ | {'S_SOURCE_ROOT': str(ROOT)}, timeout=120)
                    if result.returncode:
                        raise AssertionError((command[:3], result.returncode, result.stderr.decode(errors='replace')))
                if not seed:
                    checked = subprocess.run(['sh', str(ROOT / 'misc/scripts/verify_true_selfhost.sh'), str(binary)],
                                             capture_output=True, timeout=15)
                    if checked.returncode:
                        raise AssertionError(checked.stderr.decode(errors='replace'))
        except BaseException:
            cls.temporary.cleanup()
            raise

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def test_native_protocol(self):
        result = subprocess.run([str(self.work / 'protocol')], capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, (result.stdout, result.stderr))

    @contextmanager
    def running(self, mode='one'):
        process = subprocess.Popen([str(self.work / 'server')], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   env=os.environ | {'S_HTTP_TEST_MODE': mode})
        try:
            self.assertTrue(select.select([process.stdout], [], [], 5)[0], 'server did not report port')
            line = process.stdout.readline().strip()
            self.assertTrue(line.isdigit(), line)
            yield process, int(line)
            output, error = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 0, (output, error))
            self.assertIn(b'SHUTDOWN', output)
        finally:
            if process.poll() is None:
                process.kill()
            process.communicate()
            process.stdout.close()
            process.stderr.close()

    def receive(self, peer):
        chunks = []
        while True:
            try:
                part = peer.recv(4096)
            except ConnectionResetError:
                if not chunks:
                    raise
                break
            if not part:
                break
            chunks.append(part)
        return b''.join(chunks)

    def request(self, port, raw):
        with socket.create_connection(('127.0.0.1', port), timeout=3) as peer:
            peer.sendall(raw)
            return self.receive(peer)

    def response(self, raw, status=200, body=True):
        head, payload = raw.split(b'\r\n\r\n', 1)
        lines = head.split(b'\r\n')
        self.assertTrue(lines[0].startswith(f'HTTP/1.1 {status} '.encode()), raw)
        fields = dict(line.split(b': ', 1) for line in lines[1:])
        self.assertEqual(fields[b'Connection'], b'close')
        self.assertEqual(fields[b'Content-Type'], b'application/json')
        if body:
            self.assertEqual(int(fields[b'Content-Length']), len(payload))
            json.loads(payload)
        else:
            self.assertEqual(payload, b'')
        return fields, payload

    def test_health_json_length_close_and_graceful_shutdown(self):
        with self.running() as (process, port):
            fields, payload = self.response(self.request(port, b'GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n'))
            self.assertEqual(fields[b'Content-Length'], b'15')
            self.assertEqual(payload, b'{"status":"ok"}')
        with self.assertRaises(OSError):
            socket.create_connection(('127.0.0.1', port), timeout=.2)

    def test_fragmented_headers_head_and_routing(self):
        with self.running('three') as (_, port):
            with socket.create_connection(('127.0.0.1', port), timeout=3) as peer:
                for fragment in (b'GET /health?probe=1 HTTP/1.1\r', b'\nHost: localhost\r\n', b'\r', b'\n'):
                    peer.sendall(fragment)
                    time.sleep(.005)
                self.response(self.receive(peer))
            fields, payload = self.response(self.request(port, b'HEAD /health HTTP/1.1\r\nHost: x\r\n\r\n'), body=False)
            self.assertEqual(fields[b'Content-Length'], b'15')
            self.response(self.request(port, b'GET /missing HTTP/1.1\r\nHost: x\r\n\r\n'), 404)

    def test_malformed_and_ambiguous_requests(self):
        cases = [
            (b'GET / HTTP/1.1\r\n\r\n', 400),
            (b'GET / HTTP/1.1\r\nHost: \r\n\r\n', 400),
            (b'GET / HTTP/1.1\nHost: x\n\n', 400),
            (b'GET / HTTP/1.1\r\nHost: x\r\nHost: y\r\n\r\n', 400),
            (b'GET / HTTP/1.1\r\nHost : x\r\n\r\n', 400),
            (b'GET / HTTP/1.1\r\nHost: x\r\n folded\r\n\r\n', 400),
            (b'GET / HTTP/1.1\r\nHost: x\r\nBad@Name: y\r\n\r\n', 400),
            (b'GET / HTTP/1.1\r\nHost: x\r\nX: a\0b\r\n\r\n', 400),
            (b'GET / HTTP/1.1\r\nHost: x\r\nContent-Length: +0\r\n\r\n', 400),
            (b'GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 0, 0\r\n\r\n', 400),
            (b'GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\nContent-Length: 0\r\n\r\n', 400),
            (b'GET / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nContent-Length: 0\r\n\r\n', 400),
            (b'GET / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n', 501),
            (b'GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 999999999999999999999999\r\n\r\n', 413),
            (b'GET / HTTP/1.1\r\nHost: x\r\nExpect: 100-continue\r\n\r\n', 417),
            (b'GET /bad%GG HTTP/1.1\r\nHost: x\r\n\r\n', 400),
            (b'GET /#fragment HTTP/1.1\r\nHost: x\r\n\r\n', 400),
            (b'GET /health HTTP/1.0\r\nHost: x\r\n\r\n', 505),
            (b'POST /health HTTP/1.1\r\nHost: x\r\n\r\n', 405),
        ]
        for raw, status in cases:
            with self.subTest(raw=raw), self.running() as (_, port):
                self.response(self.request(port, raw), status)

    def test_invalid_host_authority(self):
        for host in (b':80', b'localhost:abc', b'localhost:65536', b'[::1', b'a:b:c', b'bad@host'):
            with self.subTest(host=host), self.running() as (_, port):
                self.response(self.request(port, b'GET /health HTTP/1.1\r\nHost: ' + host + b'\r\n\r\n'), 400)

    def test_byte_line_and_header_count_limits(self):
        cases = [
            (b'GET /health HTTP/1.1\r\nHost: x\r\nX: ' + b'a' * 600, 431),
            (b'GET /' + b'a' * 260 + b' HTTP/1.1\r\nHost: x\r\n\r\n', 414),
            (b'GET /health HTTP/1.1\r\nHost: x\r\n' + b'X: a\r\n' * 8 + b'\r\n', 431),
        ]
        for raw, status in cases:
            with self.subTest(status=status), self.running() as (_, port):
                self.response(self.request(port, raw), status)

    def test_idle_and_slow_header_absolute_deadline(self):
        for slow in (False, True):
            with self.subTest(slow=slow), self.running() as (_, port):
                start = time.monotonic()
                with socket.create_connection(('127.0.0.1', port), timeout=3) as peer:
                    if slow:
                        for byte in b'GET ':
                            try:
                                peer.sendall(bytes([byte]))
                            except OSError:
                                break
                            time.sleep(.06)
                    self.response(self.receive(peer), 408)
                self.assertLess(time.monotonic() - start, .8)

    def test_completed_headers_after_scheduler_pause_exceed_deadline(self):
        with self.running() as (process, port):
            with socket.create_connection(('127.0.0.1', port), timeout=3) as peer:
                peer.sendall(b'G')
                time.sleep(.03)
                os.kill(process.pid, signal.SIGSTOP)
                try:
                    peer.sendall(b'ET /health HTTP/1.1\r\nHost: x\r\n\r\n')
                    time.sleep(.2)
                finally:
                    os.kill(process.pid, signal.SIGCONT)
                self.response(self.receive(peer), 408)

    def test_errors_eof_and_reset_do_not_poison_listener(self):
        with self.running('three') as (_, port):
            with socket.create_connection(('127.0.0.1', port), timeout=3) as peer:
                peer.sendall(b'GET /health HTTP/1.1\r\nHost:')
                peer.shutdown(socket.SHUT_WR)
                self.response(self.receive(peer), 400)
            with socket.create_connection(('127.0.0.1', port), timeout=3) as peer:
                peer.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack('ii', 1, 0))
                peer.sendall(b'GET /health HTTP/1.1\r\nHost: x\r\n\r\n')
            self.response(self.request(port, b'GET /health HTTP/1.1\r\nHost: x\r\n\r\n'))

    def test_descriptor_cleanup_and_no_pipelining(self):
        with self.running('many') as (process, port):
            baseline = len(list(Path(f'/proc/{process.pid}/fd').iterdir()))
            raw = b'GET /health HTTP/1.1\r\nHost: x\r\n\r\n'
            for _ in range(47):
                result = self.request(port, raw + raw)
                self.response(result)
                self.assertEqual(result.count(b'HTTP/1.1'), 1)
                self.assertLessEqual(len(list(Path(f'/proc/{process.pid}/fd').iterdir())), baseline + 1)
            self.response(self.request(port, raw))

    def test_response_write_deadline_with_nonreading_peer(self):
        with self.running('write-timeout') as (_, port):
            with socket.socket() as peer:
                peer.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1024)
                peer.settimeout(5)
                peer.connect(('127.0.0.1', port))
                time.sleep(.3)

    def test_accept_timeout_and_invalid_config(self):
        with self.running('accept-timeout'):
            pass
        result = subprocess.run([str(self.work / 'server')], capture_output=True, timeout=5,
                                env=os.environ | {'S_HTTP_TEST_MODE': 'invalid'})
        self.assertEqual(result.returncode, 0, (result.stdout, result.stderr))


if __name__ == '__main__':
    unittest.main()
