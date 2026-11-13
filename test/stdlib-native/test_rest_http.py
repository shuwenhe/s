"""REST HTTP foundation over real sockets, identical native and Seed closure."""
from contextlib import contextmanager
from pathlib import Path
import os
import select
import socket
import struct
import subprocess
import tempfile
import time
import unittest
ROOT = Path(__file__).resolve().parents[2]
class RestHTTPTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='s-rest-http-')
        cls.work = Path(cls.temp.name)
        cls.binaries = []
        sources = [ROOT/'src/std/tcp.s', ROOT/'src/std/time.s', ROOT/'src/result/result.s', ROOT/'src/option/option.s', ROOT/'src/prelude/prelude.s', *sorted((ROOT/'src/std/http').glob('*.s')), ROOT/'test/rest/server.s']
        for seed in (False,True):
            compiler = ROOT/'bin/s_seed' if seed else Path(os.environ.get('S_TEST_COMPILER', ROOT/'bin/s_compiler'))
            unit = cls.work/('seed.ir' if seed else 'native.sasm')
            binary = cls.work/('seed' if seed else 'native')
            for command in ([str(compiler),'--compile-native-unit' if seed else '--compile-unit',str(unit),*map(str,sources)], [str(compiler),'--emit-standalone-amd64' if seed else '--emit-bin',str(unit),str(binary)]):
                result = subprocess.run(command,cwd=ROOT,capture_output=True,env=os.environ|{'S_SOURCE_ROOT':str(ROOT)},timeout=120)
                if result.returncode: raise AssertionError((command,result.returncode,result.stdout,result.stderr))
            cls.binaries.append(binary)
    @classmethod
    def tearDownClass(cls): cls.temp.cleanup()
    @contextmanager
    def running(self,binary,mode='one'):
        p=subprocess.Popen([str(binary)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=os.environ|{'S_REST_TEST_MODE':mode})
        try:
            self.assertTrue(select.select([p.stdout],[],[],5)[0], 'port timeout')
            line=p.stdout.readline().strip()
            self.assertTrue(line.isdigit(),(line,p.poll(),p.stderr.read() if p.poll() is not None else b''))
            yield p,int(line)
            out,err=p.communicate(timeout=5)
            self.assertEqual(p.returncode,0,(out,err))
            self.assertIn(b'SHUTDOWN',out)
        finally:
            if p.poll() is None: p.kill()
            p.communicate()
            p.stdout.close(); p.stderr.close()
    def receive(self,peer):
        out=b''
        while True:
            try: part=peer.recv(4096)
            except ConnectionResetError: break
            if not part: return out
            out+=part
        return out
    def request(self,port,raw,halfclose=False):
        with socket.create_connection(('127.0.0.1',port),timeout=3) as peer:
            peer.sendall(raw)
            if halfclose: peer.shutdown(socket.SHUT_WR)
            return self.receive(peer)
    def response(self,raw,status=200,payload=None):
        head,body=raw.split(b'\r\n\r\n',1)
        lines=head.split(b'\r\n')
        self.assertTrue(lines[0].startswith(f'HTTP/1.1 {status} '.encode()),raw)
        fields=dict(line.split(b': ',1) for line in lines[1:])
        self.assertEqual(fields[b'Connection'],b'close')
        self.assertEqual(int(fields[b'Content-Length']),len(body))
        if payload is not None: self.assertEqual(body,payload)
        return body
    def test_body_framing_rejections(self):
        cases=[(b'Content-Length: +2\r\n',b'{}',400),(b'Content-Length: 2, 2\r\n',b'{}',400),(b'Content-Length: 2\r\nContent-Length: 2\r\n',b'{}',400),(b'Transfer-Encoding: chunked\r\nContent-Length: 2\r\n',b'{}',400),(b'Transfer-Encoding: chunked\r\n',b'',501),(b'Content-Length: 33\r\n',b'',413),(b'Content-Length: 99999999999999999999\r\n',b'',413)]
        for binary in self.binaries:
            for headers,body,status in cases:
                with self.subTest(binary=binary.name,headers=headers),self.running(binary) as (_,port):
                    self.response(self.request(port,b'POST / HTTP/1.1\r\nHost: x\r\n'+headers+b'\r\n'+body),status)
    def test_fragmented_utf8_body_and_exact_bound(self):
        for binary in self.binaries:
            for body in ('{"name":"中"}'.encode(),b'['+b' '*30+b']'):
                with self.subTest(binary=binary.name,body=body),self.running(binary) as (_,port):
                    with socket.create_connection(('127.0.0.1',port),timeout=3) as peer:
                        raw=b'POST / HTTP/1.1\r\nHost: x\r\nContent-Length: '+str(len(body)).encode()+b'\r\n\r\n'+body
                        for start in range(0,len(raw),7): peer.sendall(raw[start:start+7]); time.sleep(.002)
                        self.response(self.receive(peer),payload=body)
    def test_truncated_body_and_absolute_body_timeout(self):
        for binary in self.binaries:
            with self.subTest(binary=binary.name,truncated=True),self.running(binary) as (_,port):
                self.response(self.request(port,b'POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\n\r\n{}',True),400)
            with self.subTest(binary=binary.name,timeout=True),self.running(binary) as (_,port):
                started=time.monotonic()
                self.response(self.request(port,b'POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\n\r\n{'),408)
                self.assertLess(time.monotonic()-started,1.0)
    def test_headers_query_eof_disconnect_and_repetition(self):
        for binary in self.binaries:
            with self.subTest(binary=binary.name),self.running(binary,'many') as (p,port):
                for i in range(24):
                    if i==0:
                        with socket.create_connection(('127.0.0.1',port),timeout=3): pass
                    elif i==1:
                        with socket.create_connection(('127.0.0.1',port),timeout=3) as peer:
                            peer.setsockopt(socket.SOL_SOCKET,socket.SO_LINGER,struct.pack('ii',1,0))
                            peer.sendall(b'POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 2\r\n\r\n{}')
                    else:
                        self.response(self.request(port,b'PUT /inspect?q=a%20b HTTP/1.1\r\nHost: x\r\nx-PrObE: value\r\nContent-Length: 0\r\n\r\n'),payload=b'q=a%20b|value')
                    if i < 23: self.assertIsNone(p.poll())
    def test_header_limits_idle_timeout_and_extra_body_bytes(self):
        for binary in self.binaries:
            with self.subTest(binary=binary.name,oversized=True),self.running(binary) as (_,port):
                self.response(self.request(port,b'POST / HTTP/1.1\r\nHost: x\r\nX: '+b'a'*520),431)
            with self.subTest(binary=binary.name,idle=True),self.running(binary) as (_,port):
                with socket.create_connection(('127.0.0.1',port),timeout=3) as peer:
                    self.response(self.receive(peer),408)
            with self.subTest(binary=binary.name,extra=True),self.running(binary) as (_,port):
                self.response(self.request(port,b'POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 2\r\n\r\n{}ignored'),payload=b'{}')
    def test_head_errors_preserve_method_and_never_send_body(self):
        cases = [
            (b'HEAD / HTTP/1.1\r\nHost: x\r\nContent-Length: 33\r\n\r\n', False, 413),
            (b'HEAD / HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\n\r\n{}', True, 400),
            (b'HEAD ', False, 408),
        ]
        for binary in self.binaries:
            for request,halfclose,status in cases:
                with self.subTest(binary=binary.name,status=status), self.running(binary) as (_,port):
                    raw = self.request(port,request,halfclose)
                    head,body = raw.split(b'\r\n\r\n',1)
                    lines = head.split(b'\r\n')
                    self.assertTrue(lines[0].startswith(f'HTTP/1.1 {status} '.encode()),raw)
                    fields = dict(line.split(b': ',1) for line in lines[1:])
                    self.assertEqual(fields[b'Content-Length'],b'2')
                    self.assertEqual(body,b'', 'HEAD error responses must suppress the error body')
    def test_response_injection_closes_and_server_continues(self):
        for binary in self.binaries:
            with self.subTest(binary=binary.name),self.running(binary,'two') as (_,port):
                self.assertEqual(self.request(port,b'GET /unsafe HTTP/1.1\r\nHost: x\r\n\r\n'),b'')
                self.response(self.request(port,b'DELETE / HTTP/1.1\r\nHost: x\r\n\r\n'),payload=b'{}')
if __name__=='__main__': unittest.main()
