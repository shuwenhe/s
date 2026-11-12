"""Real MySQL integration only. Require explicit isolated server configuration."""
import json, os, subprocess, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class MySQLIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not os.environ.get('S_MYSQL_PORT'):return
        cls._collecting=True;cls._bodies=[]
        try:
            for name in sorted(n for n in dir(cls) if n.startswith('test_')):
                case=cls(name);getattr(case,name)()
        finally:cls._collecting=False
        cls._work=tempfile.TemporaryDirectory(prefix='s-mysql-suite-')
        work=Path(cls._work.name);source=work/'suite.s';cls._binary=work/'suite'
        text='package main\nimport ("std.mysql"; "std.database"; "std.prelude"; "std.crypto"; "std.time")\nextern "intrinsic" func runtime_env_get(string key, string fallback) string\n'
        for index,body in enumerate(cls._bodies):
            text+=f'func case_{index}(std.database.options config) int {{\n'+body+'\n}\n'
        text+='func main() int {\n    port,error := std.database.parse_integer(runtime_env_get("S_MYSQL_PORT","0"))\n    config := std.database.options { host: "127.0.0.1", port: port, user: runtime_env_get("S_MYSQL_TEST_USER","s_native"), password: runtime_env_get("S_MYSQL_TEST_PASSWORD","s_password"), database_name: "s_driver_test", read_timeout_ms: 2000, write_timeout_ms: 2000, connect_timeout_ms: 2000, tls_server_name: runtime_env_get("S_MYSQL_TEST_TLS_HOST",""), tls_ca_file: runtime_env_get("S_MYSQL_TEST_CA",""), server_public_key: runtime_env_get("S_MYSQL_TEST_KEY",""), allow_public_key_retrieval: runtime_env_get("S_MYSQL_TEST_RETRIEVAL","0") == "1" }\n    selected := runtime_env_get("S_MYSQL_TEST_CASE","")\n'
        for index in range(len(cls._bodies)):text+=f'    if selected == "{index}" {{ return case_{index}(config) }}\n'
        text+='    return 99\n}\n';source.write_text(text)
        build=subprocess.run(['python3',str(ROOT/'misc/scripts/build-openssl-client.py'),str(source),'-o',str(cls._binary)],cwd=ROOT,capture_output=True,timeout=300)
        if build.returncode:cls._work.cleanup();raise AssertionError(build.stderr.decode(errors='replace'))
    @classmethod
    def tearDownClass(cls):
        if hasattr(cls,'_work'):cls._work.cleanup();del cls._binary
    def build_run(self, body, user='s_native', password='s_password', tls=False, expected=0, retrieval=False, public_key='', tls_hostname='localhost', target_port=None):
        cls=type(self)
        if getattr(cls,'_collecting',False):
            if body not in cls._bodies:cls._bodies.append(body)
            return
        if hasattr(cls,'_binary'):
            if os.environ.get('S_MYSQL_FLUSH_COMMAND'):
                subprocess.run(json.loads(os.environ['S_MYSQL_FLUSH_COMMAND']),check=True,capture_output=True,timeout=20)
            env=os.environ|{'S_MYSQL_TEST_CASE':str(cls._bodies.index(body)),'S_MYSQL_TEST_USER':user,'S_MYSQL_TEST_PASSWORD':password,'S_MYSQL_TEST_TLS_HOST':tls_hostname if tls else '', 'S_MYSQL_TEST_CA':os.environ['S_MYSQL_CA'] if tls else '', 'S_MYSQL_TEST_KEY':public_key,'S_MYSQL_TEST_RETRIEVAL':'1' if retrieval else '0'}
            if target_port is not None:env['S_MYSQL_PORT']=str(target_port)
            run=subprocess.run([str(cls._binary)],env=env,capture_output=True,timeout=30)
            self.assertEqual(run.returncode,expected,(run.returncode,run.stdout,run.stderr))
            return run
        port=int(os.environ['S_MYSQL_PORT'])
        if os.environ.get('S_MYSQL_FLUSH_COMMAND'):
            subprocess.run(json.loads(os.environ['S_MYSQL_FLUSH_COMMAND']),check=True,capture_output=True,timeout=20)
        with tempfile.TemporaryDirectory(prefix='s-mysql-live-') as directory:
            work=Path(directory);source=work/'main.s';binary=work/'client'
            tls_fields=', allow_public_key_retrieval: '+('true' if retrieval else 'false')+', server_public_key: '+json.dumps(public_key)
            if tls:
                tls_fields+=', tls_server_name: '+json.dumps(tls_hostname)+', tls_ca_file: '+json.dumps(os.environ['S_MYSQL_CA'])
            source.write_text('package main\nimport ("std.mysql"; "std.database"; "std.prelude"; "std.crypto"; "std.time")\nfunc main() int {\n'
                + f'config := std.database.options {{ host: "127.0.0.1", port: {port}, user: {json.dumps(user)}, password: {json.dumps(password)}, database_name: "s_driver_test", read_timeout_ms: 2000, write_timeout_ms: 2000, connect_timeout_ms: 2000{tls_fields} }}\n'
                + body+'\n}\n')
            build=subprocess.run(['python3',str(ROOT/'misc/scripts/build-openssl-client.py'),str(source),'-o',str(binary)],cwd=ROOT,capture_output=True,timeout=180)
            self.assertEqual(build.returncode,0,build.stderr.decode(errors='replace'))
            run=subprocess.run([str(binary)],capture_output=True,timeout=30)
            self.assertEqual(run.returncode,expected,(run.returncode,run.stdout,run.stderr))
            return run
    def setUp(self):
        if not os.environ.get('S_MYSQL_PORT'):self.skipTest('requires S_MYSQL_PORT pointing to a real provisioned MySQL server')
    def test_native_connect_ping_close(self):
        self.build_run('''
    connection,error := std.mysql.connect(config)
    if error.code != 0 { println(error.message); return 1 }
    if std.mysql.ping(connection*).code != 0 { return 2 }
    if std.mysql.close(connection*).code != 0 { return 3 }
    if std.mysql.close(connection*).code != 0 { return 4 }
    if std.mysql.ping(connection*).code != std.database.error_closed { return 5 }
    return 0''')
    def test_authentication_failure(self):
        self.build_run('''connection,error := std.mysql.connect(config)
    if error.code == 0 { std.mysql.close(connection*); return 1 }
    if error.native_code != 1045 { println(error.message); return 2 }
    return 0''',password='wrong_password')
    def test_crud_types_null_utf8_and_error_recovery(self):
        self.build_run('''connection,error := std.mysql.connect(config)
    if error.code != 0 { println(error.message); return 1 }
    created,ce := std.mysql.exec(connection*,"CREATE TEMPORARY TABLE driver_crud (id BIGINT, u BIGINT UNSIGNED, d DECIMAL(30,10), v VARCHAR(100), t TEXT, b BLOB, dt DATETIME(6), n INT NULL)")
    if ce.code != 0 { println(ce.message); return 2 }
    inserted,ie := std.mysql.exec(connection*,"INSERT INTO driver_crud VALUES (-9223372036854775808,18446744073709551615,12345678901234567890.1234567890,'中文你好','UTF-8测试',X'610062ff','2026-11-12 12:34:56.123456',NULL)")
    if ie.code != 0 { println(ie.message); return 3 }
    rows,re := std.mysql.query(connection*,"SELECT * FROM driver_crud")
    if re.code != 0 { println(re.message); return 4 }
    if len(rows.data) != 1 || len(rows.column_data) != 8 { return 5 }
    values := rows.data[0].values
    if !std.database.is_null(values[7]) { return 6 }
    integer,ve := std.database.as_integer(values[0])
    if ve.code != 0 || integer != -9223372036854775808 { return 7 }
    switch values[1] { std.database.value::unsigned_integer(v) : { if v != "18446744073709551615" { return 8 } }, _ : { return 9 }, }
    switch values[2] { std.database.value::decimal(v) : { if v != "12345678901234567890.1234567890" { return 10 } }, _ : { return 11 }, }
    switch values[3] { std.database.value::text(v) : { if v != "中文你好" { return 12 } }, _ : { return 13 }, }
    switch values[5] { std.database.value::binary(v) : { if std.crypto.hex(v) != "610062ff" { return 14 } }, _ : { return 15 }, }
    switch values[6] { std.database.value::timestamp(v) : { if v != "2026-11-12 12:34:56.123456" { return 16 } }, _ : { return 17 }, }
    bad,be := std.mysql.exec(connection*,"THIS IS INVALID SQL")
    if be.native_code != 1064 { return 18 }
    updated,ue := std.mysql.exec(connection*,"UPDATE driver_crud SET v='更新' WHERE n IS NULL")
    if ue.code != 0 || updated.affected_rows.unwrap() != "1" { return 19 }
    deleted,de := std.mysql.exec(connection*,"DELETE FROM driver_crud")
    if de.code != 0 || deleted.affected_rows.unwrap() != "1" { return 20 }
    return std.mysql.close(connection*).code''')
    def test_prepared_binding_binary_results_and_transactions(self):
        self.build_run('''connection,error := std.mysql.connect(config)
    if error.code != 0 { println(error.message); return 1 }
    created,ce := std.mysql.exec(connection*,"CREATE TEMPORARY TABLE driver_prepared (id BIGINT, d DECIMAL(30,10), v VARCHAR(100), b BLOB, dt DATETIME(6), n INT NULL)")
    if ce.code != 0 { return 2 }
    insert,pe := std.mysql.prepare(connection*,"INSERT INTO driver_prepared VALUES (?,?,?,?,?,?)")
    if pe.code != 0 { println(pe.message); return 3 }
    blob,he := std.crypto.unhex("610062ff")
    params := std.database.value[]{std.database.value.integer(-9223372036854775808),std.database.value.decimal("12345678901234567890.1234567890"),std.database.value.text("中文'测试"),std.database.value.binary(blob),std.database.value.timestamp("2026-11-12 12:34:56.123456"),std.database.value.null}
    if std.mysql.begin(connection*).code != 0 { return 4 }
    inserted,ie := std.mysql.statement_exec(connection*,insert*,params)
    if ie.code != 0 { println(ie.message); return 5 }
    if std.mysql.rollback(connection*).code != 0 { return 6 }
    empty,ee := std.mysql.query(connection*,"SELECT * FROM driver_prepared")
    if ee.code != 0 || len(empty.data) != 0 { return 7 }
    if std.mysql.begin(connection*).code != 0 { return 8 }
    inserted2,ie2 := std.mysql.statement_exec(connection*,insert*,params)
    if ie2.code != 0 || std.mysql.commit(connection*).code != 0 { return 9 }
    select,sp := std.mysql.prepare(connection*,"SELECT * FROM driver_prepared WHERE id=?")
    if sp.code != 0 { println(sp.message); return 10 }
    filter := std.database.value[]{std.database.value.integer(-9223372036854775808)}
    rows,re := std.mysql.statement_query(connection*,select*,filter)
    if re.code != 0 { println(re.message); return 11 }
    if len(rows.data) != 1 { return 12 }
    values := rows.data[0].values
    number,ne := std.database.as_integer(values[0])
    if ne.code != 0 || number != -9223372036854775808 || !std.database.is_null(values[5]) { return 13 }
    switch values[1] { std.database.value::decimal(v) : { if v != "12345678901234567890.1234567890" { return 14 } }, _ : { return 15 }, }
    switch values[3] { std.database.value::binary(v) : { if std.crypto.hex(v) != "610062ff" { return 16 } }, _ : { return 17 }, }
    switch values[4] { std.database.value::timestamp(v) : { if v != "2026-11-12 12:34:56.123456" { return 18 } }, _ : { return 19 }, }
    wrong,we := std.mysql.statement_exec(connection*,insert*,filter)
    if we.code != std.database.error_invalid { return 20 }
    if std.mysql.close_statement(connection*,insert*).code != 0 { return 21 }
    if std.mysql.close_statement(connection*,select*).code != 0 { return 22 }
    return std.mysql.close(connection*).code''')
    def test_sha2_full_authentication_non_tls_rsa(self):
        self.build_run('''connection,error := std.mysql.connect(config)
    if error.code != 0 { println(error.message); return 1 }
    return std.mysql.close(connection*).code''',user='s_sha2',retrieval=True)
    def test_tls_native_and_sha2(self):
        for user in ('s_native','s_sha2'):
            with self.subTest(user=user):
                self.build_run('''connection,error := std.mysql.connect(config)
    if error.code != 0 { println(error.message); return 1 }
    if !connection.encrypted { return 2 }
    if std.mysql.ping(connection*).code != 0 { return 3 }
    return std.mysql.close(connection*).code''',user=user,tls=True)
    def test_timeout_invalidates_connection(self):
        self.build_run('''connection,error := std.mysql.connect(config)
    if error.code != 0 { return 1 }
    connection.config.read_timeout_ms = 30
    rows,problem := std.mysql.query(connection*,"SELECT SLEEP(0.2)")
    if problem.code != std.database.error_transport || problem.native_code != 110 || !problem.fatal || !connection.closed { println(problem.message); return 2 }
    if std.mysql.ping(connection*).code != std.database.error_closed { return 3 }
    return std.mysql.close(connection*).code''')
    def test_server_disconnect(self):
        self.build_run('''connection,error := std.mysql.connect(config)
    if error.code != 0 { return 1 }
    other,oe := std.mysql.connect(config)
    if oe.code != 0 { return 2 }
    sql := "KILL CONNECTION " + std.prelude.to_string(connection.server_connection_id)
    result,ke := std.mysql.exec(other*,sql)
    if ke.code != 0 { println(ke.message); return 3 }
    problem := std.mysql.ping(connection*)
    if problem.code == 0 || !connection.closed { return 4 }
    return std.mysql.close(other*).code''')
    def test_sha2_full_authentication_pinned_key_then_fast_cache(self):
        key=Path(os.environ['S_MYSQL_PUBLIC_KEY']).read_text().rstrip('\0')
        self.build_run('''config.server_public_key = config.server_public_key + std.mysql._u(0,1)
    connection,error := std.mysql.connect(config)
    if error.code != 0 { println(error.message); return 1 }
    if std.mysql.close(connection*).code != 0 { return 2 }
    config.server_public_key = ""
    config.allow_public_key_retrieval = false
    cached,ce := std.mysql.connect(config)
    if ce.code != 0 { println(ce.message); return 3 }
    return std.mysql.close(cached*).code''',user='s_sha2',public_key=key)
    def test_sha2_cold_cache_without_trusted_transport_or_key_is_rejected(self):
        self.build_run('''connection,error := std.mysql.connect(config)
    if error.code != std.database.error_authentication || !connection.closed { return 1 }
    return 0''',user='s_sha2')
    def test_sha2_wrong_password(self):
        self.build_run('''connection,error := std.mysql.connect(config)
    if error.code == 0 || error.native_code != 1045 || !connection.closed { println(error.message); return 1 }
    return 0''',user='s_sha2',password='wrong_password',retrieval=True)
    def test_tls_wrong_hostname_rejected(self):
        self.build_run('''connection,error := std.mysql.connect(config)
    if error.code == 0 || !connection.closed { return 1 }
    return 0''',tls=True,tls_hostname='wrong.example')
    def test_statement_ownership_and_closed_handle(self):
        self.build_run('''connection,error := std.mysql.connect(config)
    if error.code != 0 { return 1 }
    other,oe := std.mysql.connect(config)
    if oe.code != 0 { return 2 }
    statement,se := std.mysql.prepare(connection*,"SELECT ?")
    if se.code != 0 { return 3 }
    params := std.database.value[]{std.database.value.text("safe")}
    wrong,we := std.mysql.statement_query(other*,statement*,params)
    if we.code != std.database.error_invalid { return 4 }
    duplicate := statement
    if std.mysql.close_statement(connection*,statement*).code != 0 { return 5 }
    closed,ce := std.mysql.statement_query(connection*,duplicate*,params)
    if ce.code != std.database.error_closed { return 6 }
    if std.mysql.ping(connection*).code != 0 { return 7 }
    std.mysql.close(other*)
    return std.mysql.close(connection*).code''')
    def test_buffer_limits_and_empty_values(self):
        self.build_run('''connection,error := std.mysql.connect(config)
    if error.code != 0 { return 1 }
    rows,re := std.mysql.query(connection*,"SELECT '', X'', NULL, '中文'")
    if re.code != 0 || len(rows.data) != 1 || !std.database.is_null(rows.data[0].values[2]) { return 2 }
    connection.config.max_rows = 1
    too_many,te := std.mysql.query(connection*,"SELECT 1 UNION ALL SELECT 2")
    if te.code == 0 || !connection.closed { return 3 }
    return 0''')
    def test_malformed_error_decoder_invalidates_live_connection(self):
        from mysql_failure_proxy import mysql_error_proxy
        operations={
            'query':'result,problem := std.mysql.exec(connection*,"THIS IS INVALID SQL")',
            'prepare':'result,problem := std.mysql.prepare(connection*,"THIS IS INVALID SQL")',
            'ping':'problem := std.mysql.ping(connection*)',
        }
        for operation,command in operations.items():
            body='''connection,error := std.mysql.connect(config)
    if error.code != 0 { println(error.message); return 1 }
    '''+command+'''
    if problem.code != std.database.error_protocol || !problem.fatal || !connection.closed { return 2 }
    return 0'''
            if getattr(type(self),'_collecting',False):self.build_run(body);continue
            with self.subTest(operation=operation),mysql_error_proxy(int(os.environ['S_MYSQL_PORT']),inject_ping=operation=='ping') as port:
                self.build_run(body,target_port=port)
    def test_temporal_fractional_precision_in_prepared_results(self):
        self.build_run('''connection,error := std.mysql.connect(config)
    if error.code != 0 { return 1 }
    sql := "SELECT CAST('2026-11-12 12:34:56.123' AS DATETIME(3)), CAST('12:34:56.123' AS TIME(3)), CAST('2026-11-12 12:34:56.000' AS DATETIME(3))"
    text,te := std.mysql.query(connection*,sql)
    statement,se := std.mysql.prepare(connection*,sql)
    if te.code != 0 || se.code != 0 { return 2 }
    parameters := std.database.value[]()
    rows,re := std.mysql.statement_query(connection*,statement*,parameters)
    if re.code != 0 { println(re.message); return 3 }
    data := append(text.data,rows.data[0])
    index := 0
    while index < len(data) {
        switch data[index].values[0] { std.database.value::timestamp(v) : { if v != "2026-11-12 12:34:56.123" { println(v); return 4 } }, _ : { return 5 }, }
        switch data[index].values[1] { std.database.value::time(v) : { if v != "12:34:56.123" { println(v); return 6 } }, _ : { return 7 }, }
        switch data[index].values[2] { std.database.value::timestamp(v) : { if v != "2026-11-12 12:34:56.000" { println(v); return 8 } }, _ : { return 9 }, }
        index = index + 1
    }
    if std.mysql.close_statement(connection*,statement*).code != 0 { return 10 }
    return std.mysql.close(connection*).code''')
    def test_partial_packet_and_handshake_deadline(self):
        from mysql_failure_proxy import peer
        body='''config.connect_timeout_ms = 50
    connection,error := std.mysql.connect(config)
    if error.code != std.database.error_transport || !error.fatal || !connection.closed { return 1 }
    return 0'''
        if getattr(type(self),'_collecting',False):self.build_run(body);return
        for mode in ('partial_header','partial_payload','timeout'):
            with self.subTest(fault=mode),peer(mode) as port:self.build_run(body,target_port=port)
    def test_connection_refusal(self):
        import socket
        body='''config.connect_timeout_ms = 50
    connection,error := std.mysql.connect(config)
    if error.code != std.database.error_transport || !connection.closed { return 1 }
    return 0'''
        if getattr(type(self),'_collecting',False):self.build_run(body);return
        with socket.socket() as reserved:
            reserved.bind(('127.0.0.1',0))
            self.build_run(body,target_port=reserved.getsockname()[1])
    def test_blocked_write_deadline_supplement(self):
        from mysql_failure_proxy import peer
        body='''socket,error := std.tcp.dial_ipv4(config.host,config.port,1000)
    if error.code != 0 { return 1 }
    config.write_timeout_ms = 30
    config.read_timeout_ms = 30
    config.max_packet_bytes = 16777214
    client := std.mysql.connection { socket: socket, config: config, secure: std.tls.session { closed: true } }
    payload := "x"
    index := 0
    while index < 23 { payload = payload + payload; index = index + 1 }
    problem := std.mysql._command(client*,payload)
    if problem.code != std.database.error_transport || problem.native_code != 110 || !client.closed { println(problem.message); return 2 }
    return 0'''
        if getattr(type(self),'_collecting',False):self.build_run(body);return
        with peer('blocked_write') as port:self.build_run(body,target_port=port)
    def test_outbound_limits_do_not_leak_or_desynchronize(self):
        self.build_run('''connection,error := std.mysql.connect(config)
    if error.code != 0 { return 1 }
    connection.config.max_packet_bytes = 1024
    large := "x"
    index := 0
    while index < 11 { large = large + large; index = index + 1 }
    result,problem := std.mysql.exec(connection*,large)
    if problem.code == 0 || problem.fatal || connection.closed { return 2 }
    if std.mysql.ping(connection*).code != 0 { return 3 }
    return std.mysql.close(connection*).code''')
    def test_authentication_outbound_limit_closes_partial_connection(self):
        self.build_run('''config.max_packet_bytes = 1024
    password := "p"
    index := 0
    while index < 11 { password = password + password; index = index + 1 }
    config.password = password
    connection,error := std.mysql.connect(config)
    if error.code == 0 || !error.fatal || !connection.closed { return 1 }
    return 0''',user='s_sha2',tls=True)
    def test_transaction_visibility_and_close_rolls_back(self):
        self.build_run('''connection,error := std.mysql.connect(config)
    observer,oe := std.mysql.connect(config)
    if error.code != 0 || oe.code != 0 { return 1 }
    dropped,de := std.mysql.exec(connection*,"DROP TABLE IF EXISTS driver_tx_visibility")
    created,ce := std.mysql.exec(connection*,"CREATE TABLE driver_tx_visibility (id INT PRIMARY KEY) ENGINE=InnoDB")
    if de.code != 0 || ce.code != 0 { return 2 }
    if std.mysql.begin(connection*).code != 0 { return 3 }
    inserted,ie := std.mysql.exec(connection*,"INSERT INTO driver_tx_visibility VALUES (1)")
    before,be := std.mysql.query(observer*,"SELECT id FROM driver_tx_visibility")
    if ie.code != 0 || be.code != 0 || len(before.data) != 0 { return 4 }
    if std.mysql.commit(connection*).code != 0 { return 5 }
    visible,ve := std.mysql.query(observer*,"SELECT id FROM driver_tx_visibility")
    if ve.code != 0 || len(visible.data) != 1 { return 6 }
    if std.mysql.begin(connection*).code != 0 { return 7 }
    discarded,di := std.mysql.exec(connection*,"INSERT INTO driver_tx_visibility VALUES (2)")
    if di.code != 0 || std.mysql.rollback(connection*).code != 0 { return 8 }
    after,ae := std.mysql.query(observer*,"SELECT id FROM driver_tx_visibility")
    if ae.code != 0 || len(after.data) != 1 { return 9 }
    if std.mysql.begin(connection*).code != 0 { return 10 }
    abandoned,ab := std.mysql.exec(connection*,"INSERT INTO driver_tx_visibility VALUES (3)")
    if ab.code != 0 || std.mysql.close(connection*).code != 0 { return 11 }
    replacement,rr := std.mysql.exec(observer*,"INSERT INTO driver_tx_visibility VALUES (3)")
    if rr.code != 0 { println(rr.message); return 12 }
    cleaned,cl := std.mysql.exec(observer*,"DROP TABLE driver_tx_visibility")
    if cl.code != 0 { return 13 }
    return std.mysql.close(observer*).code''')
if __name__=='__main__':unittest.main()
