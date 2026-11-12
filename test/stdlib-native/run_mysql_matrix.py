#!/usr/bin/env python3
"""Provision isolated real MySQL 8.0 and 8.4, run S integration tests and benchmarks.

Requires mysqld 8.0, mysql/mysqladmin, Docker with a MySQL 8.4 image, OpenSSL
headers, Python cryptography and a native S compiler. Never uses system services.
All temporary servers and files are removed in finally, including on failures.
"""
from pathlib import Path
import argparse, datetime, hashlib, json, os, platform, pwd, re, secrets, shutil, socket, subprocess, tempfile, time
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
ROOT=Path(__file__).resolve().parents[2]

def command(args, **kwargs):
    return subprocess.run(list(map(str,args)),check=True,capture_output=True,text=True,timeout=kwargs.pop('timeout',120),**kwargs)
def port():
    with socket.socket() as sock:sock.bind(('127.0.0.1',0));return sock.getsockname()[1]
def certificates(work):
    work.mkdir();now=datetime.datetime.now(datetime.timezone.utc)
    key=rsa.generate_private_key(public_exponent=65537,key_size=2048)
    name=x509.Name([x509.NameAttribute(x509.NameOID.COMMON_NAME,'S MySQL integration CA')])
    ca=(x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(now-datetime.timedelta(days=1)).not_valid_after(now+datetime.timedelta(days=2)).add_extension(x509.BasicConstraints(ca=True,path_length=None),True).sign(key,hashes.SHA256()))
    server_key=rsa.generate_private_key(public_exponent=65537,key_size=2048)
    server=(x509.CertificateBuilder().subject_name(x509.Name([x509.NameAttribute(x509.NameOID.COMMON_NAME,'localhost')])).issuer_name(name).public_key(server_key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(now-datetime.timedelta(days=1)).not_valid_after(now+datetime.timedelta(days=2)).add_extension(x509.SubjectAlternativeName([x509.DNSName('localhost')]),False).sign(key,hashes.SHA256()))
    for filename,content in [('ca.pem',ca.public_bytes(serialization.Encoding.PEM)),('server-cert.pem',server.public_bytes(serialization.Encoding.PEM)),('server-key.pem',server_key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()))]:
        path=work/filename;path.write_bytes(content);path.chmod(0o644)
    work.chmod(0o755)
def wait_for(admin):
    deadline=time.monotonic()+90
    while time.monotonic()<deadline:
        try:command([*admin,'SELECT 1'],timeout=5);return
        except (subprocess.SubprocessError,OSError):time.sleep(.5)
    raise RuntimeError('real MySQL server did not become ready')
SQL="""CREATE DATABASE s_driver_test CHARACTER SET utf8mb4;
CREATE USER 's_native'@'%' IDENTIFIED WITH mysql_native_password BY 's_password';
CREATE USER 's_sha2'@'%' IDENTIFIED WITH caching_sha2_password BY 's_password';
GRANT ALL ON s_driver_test.* TO 's_native'@'%','s_sha2'@'%';"""
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mysql80',default='/usr/sbin/mysqld');parser.add_argument('--image84',default='mysql:8.4')
    parser.add_argument('--compiler',action='append',type=Path);parser.add_argument('--output',type=Path,default=ROOT/'.bootstrap/mysql-results')
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True)
    compilers=args.compiler or [Path(os.environ.get('S_TEST_COMPILER',ROOT/'bin/s_compiler'))]
    records=[];failed=False
    metadata={'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'platform':platform.platform(),'python':platform.python_version()}
    if Path('/proc/cpuinfo').exists():
        metadata['cpu']=next((line.split(':',1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines() if line.startswith('model name')),'unknown')
    with tempfile.TemporaryDirectory(prefix='s-mysql-matrix-') as directory:
        work=Path(directory);work.chmod(0o755);cert=work/'cert';certificates(cert)
        for version in ('8.0','8.4'):
            container=None;server=None;data=work/version;data.mkdir();socket_path=data/'mysql.sock';listen=port()
            try:
                if version=='8.0':
                    actual=command([args.mysql80,'--version']).stdout.strip()
                    if 'Ver 8.0.' not in actual:raise RuntimeError('8.0 binary required: '+actual)
                    command([args.mysql80,'--no-defaults','--initialize-insecure','--user='+pwd.getpwuid(os.getuid()).pw_name,'--datadir='+str(data/'data'),'--log-error='+str(data/'init.log')])
                    server=subprocess.Popen([args.mysql80,'--no-defaults','--user='+pwd.getpwuid(os.getuid()).pw_name,'--datadir='+str(data/'data'),'--socket='+str(socket_path),'--pid-file='+str(data/'pid'),'--port='+str(listen),'--bind-address=127.0.0.1','--mysqlx=OFF','--ssl-ca='+str(cert/'ca.pem'),'--ssl-cert='+str(cert/'server-cert.pem'),'--ssl-key='+str(cert/'server-key.pem'),'--log-error='+str(data/'server.log')],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
                    admin=['mysql','--no-defaults','--socket='+str(socket_path),'-uroot','-N','-B','-e']
                    key=data/'data/public_key.pem'
                else:
                    container='s-mysql-driver-'+secrets.token_hex(6);password=secrets.token_hex(20)
                    command(['docker','run','-d','--name',container,'-e','MYSQL_ROOT_PASSWORD='+password,'-p',f'127.0.0.1:{listen}:3306','--mount',f'type=bind,src={cert},dst=/s-test-certs,readonly',args.image84,'--mysql-native-password=ON','--ssl-ca=/s-test-certs/ca.pem','--ssl-cert=/s-test-certs/server-cert.pem','--ssl-key=/s-test-certs/server-key.pem'])
                    admin=['docker','exec','-e','MYSQL_PWD='+password,container,'mysql','--protocol=TCP','-h127.0.0.1','-P3306','-uroot','-N','-B','-e'];key=data/'public_key.pem'
                wait_for(admin)
                actual=command([*admin,'SELECT VERSION()']).stdout.strip()
                if not actual.startswith(version+'.'):raise RuntimeError(f'expected {version}, got {actual}')
                command([*admin,SQL])
                if container:command(['docker','cp',container+':/var/lib/mysql/public_key.pem',str(key)])
                for compiler in compilers:
                    compiler=compiler.resolve();label=version+'-'+compiler.parent.name+'-'+compiler.name
                    env=os.environ|{'S_MYSQL_PORT':str(listen),'S_MYSQL_CA':str(cert/'ca.pem'),'S_MYSQL_PUBLIC_KEY':str(key),'S_MYSQL_FLUSH_COMMAND':json.dumps([*admin,'FLUSH PRIVILEGES']),'S_TEST_COMPILER':str(compiler)}
                    record={'server':actual,'compiler':str(compiler),'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'test_exit':None,'benchmarks':[], 'driver_sha256':{str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted((ROOT/'src/std/mysql').glob('*.s'))}}
                    tests=subprocess.run(['python3',str(ROOT/'test/stdlib-native/test_mysql_integration.py'),'-v'],cwd=ROOT,env=env,capture_output=True,text=True,timeout=1800)
                    (args.output/(label+'.log')).write_text(tests.stdout+tests.stderr);record['test_exit']=tests.returncode;failed|=tests.returncode!=0
                    count=re.search(r'Ran (\d+) tests?',tests.stderr)
                    record['tests_run']=int(count.group(1)) if count else 0
                    print(label,tests.stderr[-2000:],flush=True)
                    if tests.returncode==0:
                        for tls in ('0','1'):
                            benchmark=subprocess.run(['python3',str(ROOT/'test/stdlib-native/benchmark_mysql.py')],cwd=ROOT,env=env|{'S_MYSQL_BENCH_TLS':tls},capture_output=True,text=True,timeout=300)
                            record['benchmarks'].append({'tls':tls=='1','exit':benchmark.returncode,'output':benchmark.stdout,'stderr':benchmark.stderr});failed|=benchmark.returncode!=0
                    records.append(record)
            except Exception as error:
                failed=True
                detail=(error.stderr or error.stdout or f'command exited {error.returncode}') if isinstance(error,subprocess.CalledProcessError) else str(error)
                if container:detail=detail.replace(password,'<redacted>')
                records.append({'server_target':version,'error':detail});print(version,type(error).__name__,detail,flush=True)
            finally:
                if container:
                    logs=subprocess.run(['docker','logs',container],capture_output=True,text=True,timeout=30)
                    (args.output/(version+'-server.log')).write_text((logs.stdout+logs.stderr).replace(password,'<redacted>'))
                    subprocess.run(['docker','rm','-f',container],capture_output=True,timeout=30)
                if server:
                    server.terminate()
                    try:server.wait(30)
                    except subprocess.TimeoutExpired:server.kill();server.wait()
                for name in ('init.log','server.log'):
                    if (data/name).exists():shutil.copyfile(data/name,args.output/(version+'-'+name))
                (args.output/'results.json').write_text(json.dumps({'environment':metadata,'results':records},indent=2))
    return int(failed)
if __name__=='__main__':raise SystemExit(main())
