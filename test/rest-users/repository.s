package main
import ("std.mysql"; "std.database"; "std.json"; "std.prelude")

// A statement is owned here, closed on every path before returning buffered rows.
func repo_query(std.mysql.connection* client, string sql, std.database.value[] parameters) (std.database.rows,std.database.error) {
    statement,error := std.mysql.prepare(client*,sql)
    if error.code != 0 { return std.database.rows {},error }
    rows,query_error := std.mysql.statement_query(client*,statement*,parameters)
    closed := std.mysql.close_statement(client*,statement*)
    if query_error.code != 0 { return rows,query_error }
    return rows,closed
}
func repo_exec(std.mysql.connection* client, string sql, std.database.value[] parameters) (std.database.result,std.database.error) {
    statement,error := std.mysql.prepare(client*,sql)
    if error.code != 0 { return std.database.result {},error }
    result,execute_error := std.mysql.statement_exec(client*,statement*,parameters)
    closed := std.mysql.close_statement(client*,statement*)
    if execute_error.code != 0 { return result,execute_error }
    return result,closed
}
func user_json(std.database.row row) string {
    if len(row.values) != 4 { return "" }
    id,error := std.database.as_integer(row.values[0])
    if error.code != 0 || id < 1 { return "" }
    name := ""
    email := ""
    valid := false
    switch row.values[1] { std.database.value::text(value) : { name = value; valid = true }, _ : {}, }
    if !valid { return "" }
    valid = false
    switch row.values[2] { std.database.value::text(value) : { email = value; valid = true }, _ : {}, }
    if !valid { return "" }
    nq,ne := std.json.quote(name)
    eq,ee := std.json.quote(email)
    if ne.code != 0 || ee.code != 0 { return "" }
    age := "null"
    if !std.database.is_null(row.values[3]) {
        number,problem := std.database.as_integer(row.values[3])
        if problem.code != 0 { return "" }
        age = std.prelude.to_string(number)
    }
    return "{\"id\":\"" + std.prelude.to_string(id) + "\",\"name\":" + nq + ",\"email\":" + eq + ",\"age\":" + age + "}"
}
struct user_input { string name, string email, std.database.value age, bool valid }
func parse_user(string body) user_input {
    invalid := user_input { age: std.database.value.null }
    doc,error := std.json.parse(body,std.json.limits { max_bytes: 65536, max_depth: 16, max_nodes: 64 })
    if error.code != 0 || std.json.kind(doc,0) != "object" { return invalid }
    n := std.json.get(doc,0,"name")
    e := std.json.get(doc,0,"email")
    if std.json.kind(doc,n) != "string" || std.json.kind(doc,e) != "string" { return invalid }
    name := std.json.text(doc,n)
    email := std.json.text(doc,e)
    if len(name) == 0 || len(name) > 200 || len(email) < 3 || len(email) > 254 { return invalid }
    at := 0
    index := 0
    while index < len(email) {
        b := std.database._byte(email,index)
        if b <= 32 || b >= 127 { return invalid }
        if b == 64 { at = at + 1; if index == 0 || index == len(email) - 1 { return invalid } }
        index = index + 1
    }
    if at != 1 { return invalid }
    index = 1
    while index < doc.count {
        node := doc.nodes[index]
        if node.parent == 0 && node.key != "name" && node.key != "email" && node.key != "age" { return invalid }
        index = index + 1
    }
    age := std.database.value.null
    a := std.json.get(doc,0,"age")
    if a >= 0 && std.json.kind(doc,a) != "null" {
        if std.json.kind(doc,a) != "number" { return invalid }
        number,problem := std.database.parse_integer(std.json.text(doc,a))
        if problem.code != 0 || number < 0 || number > 150 { return invalid }
        age = std.database.value.integer(number)
    }
    return user_input { name: name, email: email, age: age, valid: true }
}
