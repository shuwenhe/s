#!/usr/bin/env python3
"""Measure real-server latency using the same native S client as integration tests."""
import json, os
from test_mysql_integration import MySQLIntegrationTests
if __name__=='__main__':
    case=MySQLIntegrationTests()
    iterations=int(os.environ.get('S_MYSQL_BENCH_ITERATIONS','100'))
    if iterations < 1 or iterations > 10000:raise SystemExit('iterations must be 1..10000')
    body='''connection,error := std.mysql.connect(config)
    if error.code != 0 { println(error.message); return 1 }
    println("server=" + connection.server_version)
    started,clock_error := std.time.monotonic_clock()
    index := 0
    while index < ITERATIONS {
        if std.mysql.ping(connection*).code != 0 { return 2 }
        index = index + 1
    }
    finished,end_error := std.time.monotonic_clock()
    println("ping_ns_per_operation=" + std.prelude.to_string((finished - started) / ITERATIONS))
    started2,clock_error2 := std.time.monotonic_clock()
    index = 0
    while index < ITERATIONS {
        rows,problem := std.mysql.query(connection*,"SELECT 1, '中文', NULL")
        if problem.code != 0 || len(rows.data) != 1 { return 3 }
        index = index + 1
    }
    finished2,end_error2 := std.time.monotonic_clock()
    println("select_ns_per_operation=" + std.prelude.to_string((finished2 - started2) / ITERATIONS))
    statement,prepare_error := std.mysql.prepare(connection*,"SELECT ?")
    if prepare_error.code != 0 { return 4 }
    parameters := std.database.value[]{std.database.value.integer(42)}
    started3,clock_error3 := std.time.monotonic_clock()
    index = 0
    while index < ITERATIONS {
        rows,problem := std.mysql.statement_query(connection*,statement*,parameters)
        if problem.code != 0 || len(rows.data) != 1 { return 5 }
        index = index + 1
    }
    finished3,end_error3 := std.time.monotonic_clock()
    println("prepared_select_ns_per_operation=" + std.prelude.to_string((finished3 - started3) / ITERATIONS))
    if std.mysql.close_statement(connection*,statement*).code != 0 { return 6 }
    return std.mysql.close(connection*).code'''.replace('ITERATIONS',str(iterations))
    # The harness import intentionally includes std.time explicitly for the benchmark.
    result=case.build_run(body,tls=os.environ.get('S_MYSQL_BENCH_TLS')=='1')
    print(json.dumps({'iterations':iterations,'tls':os.environ.get('S_MYSQL_BENCH_TLS')=='1','measurements':result.stdout.decode().splitlines()},ensure_ascii=False))
