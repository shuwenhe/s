package main
import ("std.mysql"; "std.database")
extern "intrinsic" func runtime_env_get(string key, string fallback) string
func main() int {
    port,port_error := std.database.parse_integer(runtime_env_get("MYSQL_PORT","3306"))
    if port_error.code != 0 { return 1 }
    config := std.database.options { host: runtime_env_get("MYSQL_HOST","127.0.0.1"), port: port, user: runtime_env_get("MYSQL_USER",""), password: runtime_env_get("MYSQL_PASSWORD",""), database_name: runtime_env_get("MYSQL_DATABASE",""), tls_server_name: runtime_env_get("MYSQL_TLS_HOST",""), tls_ca_file: runtime_env_get("MYSQL_CA","") }
    connection,error := std.mysql.connect(config)
    if error.code != 0 { println(error.message); return 2 }
    created,create_error := std.mysql.exec(connection*,"CREATE TEMPORARY TABLE s_transfer (account BIGINT PRIMARY KEY, balance DECIMAL(20,2)) ENGINE=InnoDB")
    seeded,seed_error := std.mysql.exec(connection*,"INSERT INTO s_transfer VALUES (1,100.00),(2,0.00)")
    if create_error.code != 0 || seed_error.code != 0 { std.mysql.close(connection*); return 3 }
    if std.mysql.begin(connection*).code != 0 { std.mysql.close(connection*); return 4 }
    debit,debit_error := std.mysql.exec(connection*,"UPDATE s_transfer SET balance=balance-10 WHERE account=1")
    credit,credit_error := std.mysql.exec(connection*,"UPDATE s_transfer SET balance=balance+10 WHERE account=2")
    if debit_error.code != 0 || credit_error.code != 0 {
        std.mysql.rollback(connection*)
        std.mysql.close(connection*)
        return 5
    }
    if std.mysql.commit(connection*).code != 0 { std.mysql.close(connection*); return 6 }
    if std.mysql.begin(connection*).code != 0 { std.mysql.close(connection*); return 7 }
    discarded,discard_error := std.mysql.exec(connection*,"UPDATE s_transfer SET balance=0")
    if discard_error.code != 0 { std.mysql.rollback(connection*); std.mysql.close(connection*); return 8 }
    if std.mysql.rollback(connection*).code != 0 { std.mysql.close(connection*); return 9 }
    println("committed transfer; rolled back second change")
    return std.mysql.close(connection*).code
}
