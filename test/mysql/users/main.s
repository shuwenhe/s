package main

import (
    "std.mysql"
    "std.database"
    "std.crypto"
    "std.prelude"
)

extern "intrinsic" func runtime_env_get(string key, string fallback) string

// fail rolls back the transaction, closes the connection, and returns an error code
func fail(std.mysql.connection* connection, int code, string message) int {
    println("FAIL: " + message)
    std.mysql.rollback(connection*)
    std.mysql.close(connection*)
    return code
}

// matches validates that a query result matches the expected values
func matches(
    std.database.rows rows,
    int expected_id,
    string expected_name,
    string expected_email,
) bool {
    if len(rows.data) != 1 || len(rows.column_data) != 3 {
        return false
    }

    values := rows.data[0].values

    id, error := std.database.as_integer(values[0])
    if error.code != 0 || id != expected_id {
        return false
    }

    switch values[1] {
        std.database.value::text(name): {
            if name != expected_name {
                return false
            }
        },
        _: {
            return false
        },
    }

    switch values[2] {
        std.database.value::text(email): {
            if email != expected_email {
                return false
            }
        },
        _: {
            return false
        },
    }

    return true
}

func main() int {
    // Parse port configuration
    port, port_error := std.database.parse_integer(runtime_env_get("MYSQL_PORT", "3306"))
    if port_error.code != 0 || port < 1 || port > 65535 {
        println("FAIL: invalid MYSQL_PORT")
        return 1
    }

    // Validate database name
    database_name := runtime_env_get("MYSQL_DATABASE", "")
    if database_name != "shuwen" {
        println("FAIL: MYSQL_DATABASE must be shuwen")
        return 1
    }

    // Connect to database
    config := std.database.options {
        host: runtime_env_get("MYSQL_HOST", "127.0.0.1"),
        port: port,
        user: runtime_env_get("MYSQL_USER", ""),
        password: runtime_env_get("MYSQL_PASSWORD", ""),
        database_name: database_name,
        tls_server_name: runtime_env_get("MYSQL_TLS_HOST", ""),
        tls_ca_file: runtime_env_get("MYSQL_CA", ""),
    }

    connection, error := std.mysql.connect(config)
    if error.code != 0 {
        println("FAIL CONNECT: " + error.message)
        return 2
    }
    println("PASS AUTH shuwen.users")

    // Generate random test marker
    random, random_error := std.crypto.random_bytes(16)
    if random_error.code != 0 {
        return fail(connection*, 3, "random test marker")
    }
    marker := "s-insert-" + std.crypto.hex(random)

    names := ["张三", "李四", "王五"]

    // Begin transaction
    if std.mysql.begin(connection*).code != 0 {
        return fail(connection*, 4, "BEGIN")
    }

    // Prepare statements
    insert, prepare_error := std.mysql.prepare(
        connection*,
        "INSERT INTO users (name, email) VALUES (?, ?)",
    )
    if prepare_error.code != 0 {
        return fail(connection*, 5, prepare_error.message)
    }

    select, select_error := std.mysql.prepare(
        connection*,
        "SELECT id, name, email FROM users WHERE id = ? AND email = ?",
    )
    if select_error.code != 0 {
        return fail(connection*, 6, select_error.message)
    }

    // Insert test records and verify
    index := 0
    while index < len(names) {
        email := marker + "-" + std.prelude.to_string(index + 1) + "@example.invalid"

        parameters := std.database.value[]{
            std.database.value.text(names[index]),
            std.database.value.text(email),
        }

        inserted, insert_error := std.mysql.statement_exec(
            connection*,
            insert*,
            parameters,
        )
        if insert_error.code != 0 {
            return fail(connection*, 7, insert_error.message)
        }

        if inserted.affected_rows.unwrap() != "1" {
            return fail(connection*, 8, "INSERT affected rows")
        }

        id, id_error := std.database.parse_integer(inserted.last_insert_id.unwrap())
        if id_error.code != 0 || id < 1 {
            return fail(connection*, 9, "last insert ID")
        }

        filter := std.database.value[]{
            std.database.value.integer(id),
            std.database.value.text(email),
        }

        rows, query_error := std.mysql.statement_query(connection*, select*, filter)
        if query_error.code != 0 {
            return fail(connection*, 10, query_error.message)
        }

        if !matches(rows, id, names[index], email) {
            return fail(connection*, 11, "SELECT ID/columns/row count/UTF-8")
        }

        println("PASS INSERT affected_rows=1 last_insert_id=" + inserted.last_insert_id.unwrap())
        println("PASS SELECT name=" + names[index] + " UTF-8")

        index = index + 1
    }

    // Clean up statements
    if std.mysql.close_statement(connection*, insert*).code != 0 {
        return fail(connection*, 12, "close INSERT statement")
    }

    if std.mysql.close_statement(connection*, select*).code != 0 {
        return fail(connection*, 13, "close SELECT statement")
    }

    // Commit transaction
    if std.mysql.commit(connection*).code != 0 {
        return fail(connection*, 14, "COMMIT")
    }

    if std.mysql.close(connection*).code != 0 {
        println("FAIL CLOSE")
        return 15
    }

    println("PASS: 3 records committed and retained in shuwen.users")
    return 0
}
