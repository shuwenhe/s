"""Native cryptographic known-answer tests, independently checked with hashlib."""
from pathlib import Path
import hashlib
import hmac
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class NativeCryptoTests(unittest.TestCase):
    def execute(self, seed, body):
        with tempfile.TemporaryDirectory(prefix='s-crypto-') as directory:
            work=Path(directory)
            source,ir,binary=work/'main.s',work/'main.ir',work/'main'
            source.write_text('package main\nimport "std.crypto"\nfunc main() int {\n'+body+'\nreturn 0\n}\n')
            production=ROOT/'src/std/crypto.s'
            self.assertTrue(production.is_file(),'missing cryptographic implementation')
            compiler=ROOT/'bin'/('s_seed' if seed else 's_compiler')
            sources=[production,ROOT/'src/result/result.s',source]
            for command in ([str(compiler),'--compile-native-unit' if seed else '--compile-unit',str(ir),*map(str,sources)],
                            [str(compiler),'--emit-standalone-amd64' if seed else '--emit-bin',str(ir),str(binary)]):
                result=subprocess.run(command,cwd=ROOT,capture_output=True,timeout=60,env=os.environ|{'S_SOURCE_ROOT':str(ROOT)})
                self.assertEqual(result.returncode,0,result.stderr.decode())
            result=subprocess.run([str(binary)],capture_output=True,timeout=60)
            self.assertEqual(result.returncode,0,(result.stdout,result.stderr))

    def test_sha1_sha256_published_vectors_and_padding_boundaries(self):
        # FIPS 180-4 / RFC 6234 vectors, plus independently derived padding cases.
        vectors=[b'',b'abc',b'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
                 *[b'a'*n for n in (55,56,63,64,65,127,128)]]
        body=[]
        for index,value in enumerate(vectors):
            for name in ('sha1','sha256'):
                expected=getattr(hashlib,name)(value).hexdigest()
                body += [f'value_{name}_{index},error_{name}_{index} := std.crypto.{name}("{value.decode()}")',
                         f'if error_{name}_{index}.code != 0 || std.crypto.hex(value_{name}_{index}) != "{expected}" {{ return {index+1} }}']
        for seed in (True,False):
            with self.subTest(seed=seed):self.execute(seed,'\n'.join(body))

    def test_hmac_sha256_rfc4231_and_long_key(self):
        # RFC 4231 cases 1,2,6; includes hashing a key longer than the block size.
        vectors=[(b'\x0b'*20,b'Hi There'),(b'Jefe',b'what do ya want for nothing?'),
                 (b'\xaa'*131,b'Test Using Larger Than Block-Size Key - Hash Key First')]
        body=[]
        for i,(key,data) in enumerate(vectors):
            body += [f'key_{i},key_error_{i} := std.crypto.unhex("{key.hex()}")',
                     f'actual_{i},error_{i} := std.crypto.hmac_sha256(key_{i},"{data.decode()}")',
                     f'if key_error_{i}.code != 0 || error_{i}.code != 0 || std.crypto.hex(actual_{i}) != "{hmac.new(key,data,hashlib.sha256).hexdigest()}" {{ return {i+1} }}']
        for seed in (True,False):
            with self.subTest(seed=seed):self.execute(seed,'\n'.join(body))

    def test_pbkdf2_sha256_published_and_multiblock_vectors(self):
        # RFC 7914 section 11, plus multi-block/truncated-output oracles.
        vectors=[('passwd','salt',1,64),('password','salt',2,33)]
        body=[]
        for i,(password,salt,iterations,length) in enumerate(vectors):
            expected=hashlib.pbkdf2_hmac('sha256',password.encode(),salt.encode(),iterations,length).hex()
            body += [f'actual_{i},error_{i} := std.crypto.pbkdf2_sha256("{password}","{salt}",{iterations},{length})',
                     f'if error_{i}.code != 0 || std.crypto.hex(actual_{i}) != "{expected}" {{ return {i+1} }}']
        body += ['invalid,error := std.crypto.pbkdf2_sha256("p","s",0,32)',
                 'if error.code == 0 { return 9 }',
                 'if !std.crypto.constant_time_equal("same","same") || std.crypto.constant_time_equal("same","samf") || std.crypto.constant_time_equal("a","aa") { return 10 }']
        for seed in (True,False):
            with self.subTest(seed=seed):self.execute(seed,'\n'.join(body))

    def test_secure_random_uses_os_entropy_and_checks_bounds(self):
        body='''
    first,error := std.crypto.random_bytes(32)
    second,second_error := std.crypto.random_bytes(32)
    if error.code != 0 || second_error.code != 0 || len(first) != 32 || len(second) != 32 || first == second { return 1 }
    invalid,invalid_error := std.crypto.random_bytes(-1)
    excessive,excessive_error := std.crypto.random_bytes(65537)
    if invalid_error.code == 0 || excessive_error.code == 0 { return 2 }
'''
        for seed in (True,False):
            with self.subTest(seed=seed):self.execute(seed,body)


if __name__=='__main__':unittest.main()
