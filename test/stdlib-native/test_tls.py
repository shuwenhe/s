"""S/OpenSSL TLS interoperability with real certificates and encrypted loopback I/O."""
from pathlib import Path
import datetime
import json
import socket
import ssl
import subprocess
import tempfile
import threading
import unittest

from cryptography import x509
from cryptography.hazmat.primitives import hashes,serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

ROOT=Path(__file__).resolve().parents[2]


class NativeTLSTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary=tempfile.TemporaryDirectory(prefix='s-tls-certs-')
        cls.work=Path(cls.temporary.name)
        now=datetime.datetime.now(datetime.timezone.utc)
        key=rsa.generate_private_key(public_exponent=65537,key_size=2048)
        name=x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,'S TLS test CA')])
        ca=(x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key())
            .serial_number(x509.random_serial_number()).not_valid_before(now-datetime.timedelta(days=1))
            .not_valid_after(now+datetime.timedelta(days=10)).add_extension(x509.BasicConstraints(ca=True,path_length=0),True).sign(key,hashes.SHA256()))
        cls.ca=cls.work/'ca.pem';cls.ca.write_bytes(ca.public_bytes(serialization.Encoding.PEM))
        for expired in (False,True):
            server_key=rsa.generate_private_key(public_exponent=65537,key_size=2048)
            server_name=x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,'localhost')])
            cert=(x509.CertificateBuilder().subject_name(server_name).issuer_name(name).public_key(server_key.public_key())
                  .serial_number(x509.random_serial_number()).not_valid_before(now-datetime.timedelta(days=2))
                  .not_valid_after(now+datetime.timedelta(days=-1 if expired else 2))
                  .add_extension(x509.SubjectAlternativeName([x509.DNSName('localhost')]),False)
                  .sign(key,hashes.SHA256()))
            prefix='expired' if expired else 'valid'
            (cls.work/(prefix+'.pem')).write_bytes(cert.public_bytes(serialization.Encoding.PEM))
            (cls.work/(prefix+'.key')).write_bytes(server_key.private_bytes(serialization.Encoding.PEM,
                serialization.PrivateFormat.PKCS8,serialization.NoEncryption()))

    @classmethod
    def tearDownClass(cls):cls.temporary.cleanup()

    def exercise(self,hostname='localhost',trusted=True,expired=False):
        self.assertTrue((ROOT/'src/std/tls.s').is_file(),'missing S TLS interface')
        self.assertTrue((ROOT/'misc/scripts/build-openssl-client.py').is_file(),'missing OpenSSL build path')
        context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        prefix='expired' if expired else 'valid'
        context.load_cert_chain(self.work/(prefix+'.pem'),self.work/(prefix+'.key'))
        success=trusted and not expired and hostname=='localhost'
        errors=[]
        with socket.socket() as listener,tempfile.TemporaryDirectory(prefix='s-tls-native-') as directory:
            listener.bind(('127.0.0.1',0));listener.listen();listener.settimeout(15)
            def peer():
                try:
                    with listener.accept()[0] as connection:
                        connection.settimeout(5)
                        with context.wrap_socket(connection,server_side=True) as secure:
                            request=secure.recv(4)
                            self.assertEqual(request,b'ping')
                            secure.sendall(b'pong')
                except ssl.SSLError as error:
                    if success:errors.append(error)
                except BaseException as error:errors.append(error)
            worker=threading.Thread(target=peer,daemon=True);worker.start()
            work=Path(directory);source=work/'main.s';binary=work/'client'
            ca=str(self.ca) if trusted else str(self.work/'valid.pem')
            body=f'''
package main
import ("std.tcp"; "std.tls")
func main() int {{
    connection,error := std.tcp.dial_ipv4("127.0.0.1",{listener.getsockname()[1]},2000)
    if error.code != 0 {{ return 1 }}
    secure,tls_error := std.tls.connect(connection,{json.dumps(hostname)},{json.dumps(ca)},2000)
'''
            if success:
                body+='''
    if tls_error.code != 0 { std.tcp.close(connection*); return 2 }
    written,write_error := std.tls.write_all(secure*,"ping",1000)
    if write_error.code != 0 || written != 4 { std.tls.close(secure*); std.tcp.close(connection*); return 3 }
    reply,read_error := std.tls.read_some(secure,8,1000)
    if read_error.code != 0 || reply.data != "pong" || reply.eof { std.tls.close(secure*); std.tcp.close(connection*); return 4 }
    if std.tls.close(secure*).code != 0 || std.tls.close(secure*).code != 0 { std.tcp.close(connection*); return 5 }
'''
            else:
                body+='''
    if tls_error.code == 0 { std.tls.close(secure*); std.tcp.close(connection*); return 6 }
'''
            body+='''
    if std.tcp.close(connection*).code != 0 { return 7 }
    return 0
}
'''
            source.write_text(body)
            result=subprocess.run(['python3',str(ROOT/'misc/scripts/build-openssl-client.py'),str(source),'-o',str(binary)],cwd=ROOT,capture_output=True,timeout=90)
            self.assertEqual(result.returncode,0,result.stderr.decode())
            result=subprocess.run([str(binary)],capture_output=True,timeout=10)
            worker.join(10)
            self.assertFalse(worker.is_alive())
            self.assertFalse(errors,errors)
            self.assertEqual(result.returncode,0,(result.stdout,result.stderr))

    def test_valid_chain_hostname_handshake_encrypted_read_write_and_close(self):self.exercise()
    def test_wrong_hostname_is_rejected(self):self.exercise(hostname='wrong.example')
    def test_untrusted_certificate_is_rejected(self):self.exercise(trusted=False)
    def test_expired_certificate_is_rejected(self):self.exercise(expired=True)


if __name__=='__main__':unittest.main()
