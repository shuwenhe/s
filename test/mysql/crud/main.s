package main
import ("std.mysql"; "std.database"; "std.prelude")
extern "intrinsic" func runtime_env_get(string key, string fallback) string
func main() int {
    port,port_error := std.database.parse_integer(runtime_env_get("MYSQL_PORT","3306"))
    if port_error.code != 0 || port < 1 || port > 65535 { println(port_error.message); return 1 }
    config := std.database.options { host: runtime_env_get("MYSQL_HOST","127.0.0.1"), port: port, user: runtime_env_get("MYSQL_USER",""), password: runtime_env_get("MYSQL_PASSWORD",""), database_name: runtime_env_get("MYSQL_DATABASE",""), tls_server_name: runtime_env_get("MYSQL_TLS_HOST",""), tls_ca_file: runtime_env_get("MYSQL_CA","") }
    connection,error := std.mysql.connect(config)
    if error.code != 0 { println(error.message); return 2 }
    created,create_error := std.mysql.exec(connection*,"CREATE TEMPORARY TABLE s_people (id BIGINT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(100))")
    if create_error.code != 0 { println(create_error.message); std.mysql.close(connection*); return 3 }
    statement,prepare_error := std.mysql.prepare(connection*,"INSERT INTO s_people (name) VALUES (?)")
    if prepare_error.code != 0 { println(prepare_error.message); std.mysql.close(connection*); return 4 }
    parameters := std.database.value[]{std.database.value.text("张三")}
    inserted,insert_error := std.mysql.statement_exec(connection*,statement*,parameters)
    if insert_error.code != 0 { println(insert_error.message); std.mysql.close(connection*); return 5 }
    if inserted.affected_rows.unwrap() != "1" || inserted.last_insert_id.unwrap() != "1" { println("FAIL insert count/id"); std.mysql.close(connection*); return 11 }
    println("PASS INSERT")
    if std.mysql.close_statement(connection*,statement*).code != 0 { std.mysql.close(connection*); return 6 }
    rows,query_error := std.mysql.query(connection*,"SELECT id,name FROM s_people ORDER BY id")
    if query_error.code != 0 { println(query_error.message); std.mysql.close(connection*); return 7 }
    if len(rows.data) != 1 || len(rows.column_data) != 2 { println("FAIL select row count"); std.mysql.close(connection*); return 12 }
    index := 0
    while index < len(rows.data) {
        id,id_error := std.database.as_integer(rows.data[index].values[0])
        if id_error.code != 0 || id != 1 { std.mysql.close(connection*); return 8 }
        switch rows.data[index].values[1] {
            std.database.value::text(name) : {
                if name != "张三" { println("FAIL inserted name"); std.mysql.close(connection*); return 13 }
                println(std.prelude.to_string(id) + ": " + name)
            },
            _ : { std.mysql.close(connection*); return 9 },
        }
        index = index + 1
    }
    println("PASS SELECT")
    updated,update_error := std.mysql.exec(connection*,"UPDATE s_people SET name='李四' WHERE id=1")
    if update_error.code != 0 { println(update_error.message); std.mysql.close(connection*); return 14 }
    if updated.affected_rows.unwrap() != "1" { println("FAIL update count"); std.mysql.close(connection*); return 15 }
    changed,changed_error := std.mysql.query(connection*,"SELECT name FROM s_people WHERE id=1")
    if changed_error.code != 0 || len(changed.data) != 1 { println("FAIL updated row"); std.mysql.close(connection*); return 16 }
    switch changed.data[0].values[0] {
        std.database.value::text(name) : { if name != "李四" { println("FAIL updated name"); std.mysql.close(connection*); return 17 } },
        _ : { std.mysql.close(connection*); return 18 },
    }
    println("PASS UPDATE")
    deleted,delete_error := std.mysql.exec(connection*,"DELETE FROM s_people WHERE id=1")
    if delete_error.code != 0 { println(delete_error.message); std.mysql.close(connection*); return 10 }
    if deleted.affected_rows.unwrap() != "1" { println("FAIL delete count"); std.mysql.close(connection*); return 19 }
    remaining,remaining_error := std.mysql.query(connection*,"SELECT id FROM s_people")
    if remaining_error.code != 0 || len(remaining.data) != 0 { println("FAIL deleted row remains"); std.mysql.close(connection*); return 20 }
    println("PASS DELETE")
    println("PASS MySQL CRUD")
    return std.mysql.close(connection*).code
}
