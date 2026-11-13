"""Real HTTP/Next -> native S business logic -> MySQL. Client/harness only."""
import http.client, json, os, select, signal, socket, struct, subprocess, tempfile, time, unittest, uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
FRONTEND=ROOT/'test/rest-users/frontend'
class RESTIntegration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        for key in ('MYSQL_USER','MYSQL_PASSWORD','MYSQL_DATABASE'):
            if not os.environ.get(key): raise RuntimeError('Set '+key+' for real MySQL acceptance')
        cls.work=tempfile.TemporaryDirectory(prefix='s-rest-')
        cls.addClassCleanup(cls.emergency_cleanup)
        cls.binary=Path(cls.work.name)/'server'
        result=subprocess.run(['python3','misc/scripts/build-openssl-client.py','test/rest-users/main.s','-o',str(cls.binary)],cwd=ROOT,capture_output=True,timeout=240)
        if result.returncode: raise AssertionError(result.stderr.decode(errors='replace'))
        cls.env=os.environ|{'S_REST_PORT':'0','S_REST_MAX_REQUESTS':'256'}
        cls.app,cls.port=cls.start_app(cls.env)
        cls.created=[]
        with socket.socket() as reserve:
            reserve.bind(('127.0.0.1',0));cls.next_port=reserve.getsockname()[1]
        cls.next=subprocess.Popen(['node','node_modules/next/dist/bin/next','start','--hostname','127.0.0.1','--port',str(cls.next_port)],cwd=FRONTEND,env=os.environ|{'S_API_ORIGIN':f'http://127.0.0.1:{cls.port}','NEXT_TELEMETRY_DISABLED':'1'},stdout=subprocess.PIPE,stderr=subprocess.STDOUT,start_new_session=True)
        deadline=time.monotonic()+20
        while time.monotonic()<deadline:
            try:
                status,headers,body=cls.request_to(cls.next_port,'GET','/')
                if status==200 and b'People' in body:break
            except OSError: pass
            if cls.next.poll() is not None: raise AssertionError(cls.next.stdout.read().decode())
            time.sleep(.1)
        else:raise AssertionError('Next production server did not start')
        print('PASS Next production server / -> 200')
    @classmethod
    def emergency_cleanup(cls):
        if hasattr(cls,'app') and cls.app.poll() is None:
            cls.app.kill();cls.app.communicate()
        if hasattr(cls,'next') and cls.next.poll() is None:
            os.killpg(cls.next.pid,signal.SIGTERM);cls.next.communicate(timeout=10)
        if hasattr(cls,'work'): cls.work.cleanup()
    @classmethod
    def start_app(cls,env):
        process=subprocess.Popen([str(cls.binary)],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        if not select.select([process.stdout],[],[],15)[0]:process.kill();raise AssertionError('S server startup timeout')
        line=process.stdout.readline().decode().strip()
        if not line.startswith('READY '):
            process.terminate();out,err=process.communicate(timeout=5);raise AssertionError((line,out,err))
        if ' MYSQL 8.' not in line:process.terminate();raise AssertionError('Requires real MySQL8: '+line)
        print('PASS '+line)
        return process,int(line.split()[1])
    @staticmethod
    def request_to(port,method,path,body=None,headers=None):
        connection=http.client.HTTPConnection('127.0.0.1',port,timeout=15)
        try:
            connection.request(method,path,body,headers or {})
            result=connection.getresponse();data=result.read()
            return result.status,dict((k.lower(),v) for k,v in result.getheaders()),data
        finally:connection.close()
    def call(self,method,path,body=None,port=None,expected=200):
        headers={}
        if body is not None:body=json.dumps(body,ensure_ascii=False).encode();headers={'Content-Type':'application/json'}
        status,received,data=self.request_to(port or self.port,method,path,body,headers)
        self.assertEqual(status,expected,(method,path,status,data))
        if method=='HEAD' or status==204:self.assertEqual(data,b'');return None
        if 'content-length' in received: self.assertEqual(int(received['content-length']),len(data))
        else:
            self.assertNotEqual(port or self.port,self.port,received)
            self.assertEqual(received.get('transfer-encoding'),'chunked',received)
        self.assertTrue(received['content-type'].startswith('application/json'))
        value=json.loads(data)
        if status>=400:self.assertIsInstance(value['error']['code'],str);self.assertIsInstance(value['error']['message'],str)
        return value
    @classmethod
    def drain(cls,process,port):
        for _ in range(300):
            if process.poll() is not None:break
            try:cls.request_to(port,'GET','/health')
            except (OSError,http.client.HTTPException):time.sleep(.01)
        out,err=process.communicate(timeout=10)
        if process.returncode!=0 or b'SHUTDOWN' not in out:raise AssertionError((process.returncode,out,err))
        print('PASS S deterministic shutdown exit=0')
    @classmethod
    def tearDownClass(cls):
        try:
            for identifier in cls.created:
                cls.request_to(cls.port,'DELETE','/api/users/'+identifier)
            cls.drain(cls.app,cls.port)
        finally:
            if hasattr(cls,'app') and cls.app.poll() is None:cls.app.kill();cls.app.communicate()
            if hasattr(cls,'next'):
                if cls.next.poll() is None:os.killpg(cls.next.pid,signal.SIGTERM)
                cls.next.communicate(timeout=10)
            cls.work.cleanup()
    def exercise_crud(self,port):
        for iteration in range(2):
            email=uuid.uuid4().hex+'@s-rest.invalid'
            payload={'name':'张三😀 "\\\n','email':email,'age':None}
            user=self.call('POST','/api/users',payload,port,201)
            identifier=user['id'];self.created.append(identifier)
            self.assertTrue(identifier.isdigit());self.assertGreater(int(identifier),0)
            self.assertEqual(user['name'],payload['name']);self.assertIsNone(user['age'])
            self.assertEqual(self.call('GET','/api/users/'+identifier,port=port),user)
            selected=self.call('GET','/api/users?q=%E5%BC%A0%E4%B8%89&limit=100',port=port)['users']
            self.assertIn(identifier,[item['id'] for item in selected])
            duplicate=self.call('POST','/api/users',payload,port,409)
            self.assertEqual(duplicate['error']['code'],'conflict')
            payload['name']='李四';payload['age']=37
            updated=self.call('PUT','/api/users/'+identifier,payload,port)
            self.assertEqual(updated['name'],'李四');self.assertEqual(updated['age'],37)
            self.assertEqual(self.call('PUT','/api/users/'+identifier,payload,port),updated) # affected_rows=0 still existing
            self.call('DELETE','/api/users/'+identifier,port=port,expected=204)
            self.created.remove(identifier)
            self.call('GET','/api/users/'+identifier,port=port,expected=404)
            self.call('DELETE','/api/users/'+identifier,port=port,expected=404)
        print('PASS all5 CRUD, Unicode, NULL/integer, generatedID, conflict, repeat via '+str(port))
    def test_native_crud(self): self.exercise_crud(self.port)
    def test_next_to_native_crud(self): self.exercise_crud(self.next_port)
    def test_injection_and_transaction_rollback(self):
        email=uuid.uuid4().hex+'@s-rest.invalid'
        payload={'name':"Robert'); DROP TABLE users; --",'email':email,'age':0}
        first=self.call('POST','/api/users',payload,expected=201);self.created.append(first['id'])
        self.assertEqual(first['name'],payload['name'])
        second=self.call('POST','/api/users',payload|{'email':uuid.uuid4().hex+'@s-rest.invalid'},expected=201);self.created.append(second['id'])
        self.call('PUT','/api/users/'+second['id'],payload,expected=409)
        self.assertEqual(self.call('GET','/api/users/'+second['id']),second)
        self.call('GET',"/api/users/1%20OR%201=1",expected=400)
        self.assertEqual(self.call('GET','/api/users?q=%27%20OR%201%3D1%20--')['users'],[])
        print('PASS parameter binding and duplicate update rollback')
    def test_errors(self):
        for port in (self.port,self.next_port):
            self.call('GET','/api/users/9223372036854775808',port=port,expected=400)
            self.call('GET','/api/users?limit=101',port=port,expected=400)
            self.call('POST','/api/users',{'name':'x','email':'not-an-email'},port,400)
            self.call('POST','/api/users',{'name':'x','email':'x@y','age':1.2},port,400)
            for payload,content_type,status in [(b'{}','text/plain',415),(b'{','application/json',400),(b'\xff','application/json',400),(b'"'+b'x'*65536+b'"','application/json',413)]:
                actual,headers,data=self.request_to(port,'POST','/api/users',payload,{'Content-Type':content_type})
                self.assertEqual(actual,status,(port,actual,data))
            self.call('PATCH','/api/users',port=port,expected=405)
            if port == self.port: self.call('GET','/missing',port=port,expected=404)
            self.call('HEAD','/api/users',port=port)
        self.call('GET','/api/users?q=%FF',expected=400)
        status,headers,data=self.request_to(self.port,'PATCH','/api/users/1')
        self.assertEqual(status,405);self.assertEqual(headers['allow'],'GET, HEAD, PUT, DELETE')
        print('PASS 400/404/405/413/415 and JSON/ID/query validation')
    def test_browser_frontend(self):
        result=subprocess.run(['node','tests/browser.mjs'],cwd=FRONTEND,env=os.environ|{'NEXT_BASE_URL':f'http://127.0.0.1:{self.next_port}'},capture_output=True,timeout=120)
        print(result.stdout.decode(errors='replace'))
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))
    def test_client_reset_isolation(self):
        peer=socket.create_connection(('127.0.0.1',self.port))
        peer.sendall(b'POST /api/users HTTP/1.1\r\nHost: x\r\nContent-Length: 12\r\n\r\n{')
        peer.setsockopt(socket.SOL_SOCKET,socket.SO_LINGER,struct.pack('ii',1,0));peer.close()
        time.sleep(.1)
        self.assertEqual(self.call('GET','/health'),{'status':'ok'})
        self.assertIsNone(self.app.poll())
        print('PASS client reset isolated; listener remains live')
    def test_database_failure_is_json500(self):
        failed,port=self.start_app(self.env|{'MYSQL_MAX_RESULT_BYTES':'1','S_REST_MAX_REQUESTS':'2'})
        try:
            result=self.call('GET','/api/users',port=port,expected=500)
            self.assertEqual(result['error']['code'],'database')
            self.call('GET','/health',port=port)
            out,err=failed.communicate(timeout=10)
            self.assertEqual(failed.returncode,0,(out,err));self.assertIn(b'SHUTDOWN',out)
        finally:
            if failed.poll() is None:failed.kill();failed.communicate()
        print('PASS real database result-limit error -> JSON500 and cleanup')
if __name__=='__main__': unittest.main(verbosity=2)
