from database_test_support import NativeDatabaseCase, ROOT
class MySQLAuthTests(NativeDatabaseCase):
    def test_native_and_sha2_independent_vectors(self):
        self.execute('mysql_auth.s', [ROOT/'src/std/crypto.s', ROOT/'src/std/mysql/auth.s'])

class MySQLRSATests(NativeDatabaseCase):
    def test_oaep_ciphertext_decrypts_with_independent_rsa_implementation(self):
        for bits,exponent in ((2048,65537),(4096,65537),(2048,3)):
            with self.subTest(bits=bits,exponent=exponent):self.rsa_interoperability(bits,exponent)

    def rsa_interoperability(self, bits, exponent):
        from cryptography.hazmat.primitives.asymmetric import rsa, padding
        from cryptography.hazmat.primitives import hashes, serialization
        import json, tempfile
        from pathlib import Path
        key = rsa.generate_private_key(public_exponent=exponent, key_size=bits)
        pem = key.public_key().public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo).decode()
        pem_expression=json.dumps(pem)
        if bits==2048 and exponent==65537:
            # MySQL's generated public_key.pem includes a terminal NUL.
            pem_expression+=' + std.database.__std_byte_string(0)'
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory)/'rsa.s'
            fixture.write_text('package main\nimport ("std.mysql"; "std.crypto"; "std.database")\nfunc main() int {\n'
                + f'cipher,error := std.mysql.rsa_password("中文password","12345678901234567890",{pem_expression})\n'
                + 'if error.code != 0 { println(error.message); return 1 }\nprintln(std.crypto.hex(cipher))\nreturn 0\n}\n')
            result = self.execute(str(fixture), [ROOT/'src/std/crypto.s', ROOT/'src/std/database/wire.s', ROOT/'src/std/mysql/rsa.s'])
            cipher = bytes.fromhex(result.stdout.decode().strip())
            plain = key.decrypt(cipher, padding.OAEP(mgf=padding.MGF1(hashes.SHA1()),algorithm=hashes.SHA1(),label=None))
            password = '中文password'.encode()+b'\0'; scramble=b'12345678901234567890'
            self.assertEqual(plain, bytes(byte ^ scramble[i%20] for i,byte in enumerate(password)))

if __name__ == '__main__':
    import unittest
    unittest.main()
