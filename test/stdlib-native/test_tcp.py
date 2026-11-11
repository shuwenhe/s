"""Native S TCP tests against real loopback peers, for both compiler ABIs."""
from pathlib import Path
import os
import socket
import subprocess
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]


class NativeTCPTests(unittest.TestCase):
    def build(self, work, body, seed):
        source, intermediate, binary = work / 'main.s', work / 'main.ir', work / 'main'
        source.write_text('package main\nimport ("std.tcp"; "std.prelude")\nfunc main() int {\n' + body + '\n}\n')
        compiler = ROOT / 'bin' / ('s_seed' if seed else 's_compiler')
        sources = [ROOT / 'src/std/tcp.s', ROOT / 'src/std/time.s',
                   ROOT / 'src/result/result.s', ROOT / 'src/prelude/prelude.s', source]
        for path in sources:
            self.assertTrue(path.is_file(), f'missing TCP implementation: {path}')
        for command in ([str(compiler), '--compile-native-unit' if seed else '--compile-unit',
                         str(intermediate), *map(str, sources)],
                        [str(compiler), '--emit-standalone-amd64' if seed else '--emit-bin',
                         str(intermediate), str(binary)]):
            result = subprocess.run(command, cwd=ROOT, capture_output=True,
                                    env=os.environ | {'S_SOURCE_ROOT': str(ROOT)}, timeout=60)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
        return binary

    def test_connect_read_write_eof_close_and_connection_refusal(self):
        for seed in (True, False):
            with self.subTest(seed=seed), tempfile.TemporaryDirectory(prefix='s-tcp-') as directory:
                with socket.socket() as server:
                    server.bind(('127.0.0.1', 0)); server.listen(); server.settimeout(10)
                    errors = []
                    def peer():
                        try:
                            with server.accept()[0] as conn:
                                conn.settimeout(10)
                                request = bytearray()
                                while len(request) < 4:
                                    request.extend(conn.recv(4 - len(request)))
                                self.assertEqual(request, b'ping')
                                conn.sendall(b'p\0ng')
                                conn.shutdown(socket.SHUT_WR)
                        except BaseException as error:
                            errors.append(error)
                    worker = threading.Thread(target=peer, daemon=True); worker.start()
                    body = '''
    connection, error := std.tcp.dial_ipv4("127.0.0.1",PORT,1000)
    if error.code != 0 { return 1 }
    written, write_error := std.tcp.write_all(connection*,"ping",1000)
    if write_error.code != 0 || written != 4 { return 2 }
    data := ""
    while len(data) < 4 {
        chunk, read_error := std.tcp.read_some(connection*,4,1000)
        if read_error.code != 0 || chunk.eof { return 3 }
        data = data + chunk.data
    }
    if len(data) != 4 { return 4 }
    byte, byte_error := std.tcp.byte_at(data,1)
    if byte_error.code != 0 || byte != 0 { return 5 }
    end, end_error := std.tcp.read_some(connection*,4,1000)
    if end_error.code != 0 || !end.eof { return 6 }
    if std.tcp.close(connection*).code != 0 || std.tcp.close(connection*).code != 0 { return 7 }
    closed, closed_error := std.tcp.read_some(connection*,4,0)
    if closed_error.code == 0 { return 8 }
    refused, refused_error := std.tcp.dial_ipv4("127.0.0.1",REFUSED,100)
    if refused_error.code == 0 { std.tcp.close(refused*); return 9 }
    return 0
'''
                    # Reserved but not listening: deterministic local refusal.
                    with socket.socket() as refused:
                        refused.bind(('127.0.0.1', 0))
                        body = body.replace('PORT', str(server.getsockname()[1])).replace('REFUSED', str(refused.getsockname()[1]))
                        binary = self.build(Path(directory), body, seed)
                        result = subprocess.run([str(binary)], capture_output=True, timeout=10)
                    worker.join(10)
                    self.assertFalse(worker.is_alive())
                    self.assertFalse(errors, errors)
                    self.assertEqual(result.returncode, 0, (result.stdout, result.stderr))

    def test_accept_read_and_accept_timeouts(self):
        for seed in (True, False):
            with self.subTest(seed=seed), tempfile.TemporaryDirectory(prefix='s-tcp-listen-') as directory:
                body = '''
    listener, error := std.tcp.listen_ipv4("127.0.0.1",0,8)
    if error.code != 0 { return 1 }
    port, port_error := std.tcp.local_port(listener)
    if port_error.code != 0 { return 2 }
    timed, timeout_error := std.tcp.accept(listener,30)
    if timeout_error.code != 110 { return 3 }
    println(std.prelude.to_string(port))
    connection, accept_error := std.tcp.accept(listener,2000)
    if accept_error.code != 0 { return 4 }
    received, read_error := std.tcp.read_some(connection*,8,30)
    if read_error.code != 110 { return 5 }
    written, write_error := std.tcp.write_all(connection*,"ready",1000)
    if write_error.code != 0 || written != 5 { return 6 }
    if std.tcp.close(connection*).code != 0 || std.tcp.close(listener*).code != 0 { return 7 }
    return 0
'''
                binary = self.build(Path(directory), body, seed)
                process = subprocess.Popen([str(binary)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                try:
                    port = process.stdout.readline().strip()
                    self.assertTrue(port, process.stderr.read() if process.poll() is not None else b'no port')
                    with socket.create_connection(('127.0.0.1', int(port)), timeout=5) as peer:
                        self.assertEqual(peer.recv(5), b'ready')
                    stdout, stderr = process.communicate(timeout=10)
                    self.assertEqual(process.returncode, 0, (stdout, stderr))
                finally:
                    if process.poll() is None:
                        process.kill(); process.communicate()

    def test_partial_write_and_write_all_preserve_exact_bytes(self):
        for seed in (True, False):
            with self.subTest(seed=seed), tempfile.TemporaryDirectory(prefix='s-tcp-partial-') as directory:
                with socket.socket() as server:
                    server.bind(('127.0.0.1',0)); server.listen(); server.settimeout(10)
                    errors=[]
                    def peer():
                        try:
                            with server.accept()[0] as conn:
                                conn.settimeout(10)
                                received=bytearray()
                                while True:
                                    part=conn.recv(8192)
                                    if not part: break
                                    received.extend(part)
                                self.assertEqual(received,b'x'*131072)
                        except BaseException as error: errors.append(error)
                    worker=threading.Thread(target=peer,daemon=True); worker.start()
                    body='''
    connection, error := std.tcp.dial_ipv4("127.0.0.1",PORT,1000)
    if error.code != 0 { return 1 }
    text := "x"
    index := 0
    while index < 17 { text = text + text; index = index + 1 }
    count, partial_error := std.tcp.write_some(connection,text,0,1000)
    if partial_error.code != 0 || count <= 0 || count >= len(text) { return 2 }
    remaining, slice_error := std.tcp.slice(text,count,len(text))
    if slice_error.code != 0 { return 3 }
    written, write_error := std.tcp.write_all(connection*,remaining,1000)
    if write_error.code != 0 || written + count != len(text) { return 4 }
    if std.tcp.close(connection*).code != 0 { return 5 }
    return 0
'''.replace('PORT',str(server.getsockname()[1]))
                    binary=self.build(Path(directory),body,seed)
                    result=subprocess.run([str(binary)],capture_output=True,timeout=10)
                    worker.join(10)
                    self.assertFalse(worker.is_alive())
                    self.assertFalse(errors,errors)
                    self.assertEqual(result.returncode,0,(result.stdout,result.stderr))


if __name__ == '__main__':
    unittest.main()
