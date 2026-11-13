package main
import ("std.http"; "std.rest"; "std.mysql"; "std.database"; "std.json"; "std.prelude")
extern "intrinsic" func runtime_env_get(string key, string fallback) string

func problem(int status, string code, string message) std.http.response {
    cq,ce := std.json.quote(code)
    mq,me := std.json.quote(message)
    if ce.code != 0 || me.code != 0 { return std.http.response { status: 500, body: "{\"error\":{\"code\":\"internal\",\"message\":\"response failure\"}}" } }
    return std.http.response { status: status, body: "{\"error\":{\"code\":" + cq + ",\"message\":" + mq + "}}" }
}
func database_problem(std.database.error error) std.http.response {
    if error.native_code == 1062 { return problem(409,"conflict","email already exists") }
    return problem(500,"database","database operation failed")
}
func identifier(string text) (int,bool) {
    if len(text) == 0 || len(text) > 19 { return 0,false }
    index := 0
    while index < len(text) {
        b := std.database._byte(text,index)
        if b < 48 || b > 57 { return 0,false }
        index = index + 1
    }
    id,error := std.database.parse_integer(text)
    return id,error.code == 0 && id > 0
}
func json_content_type(std.http.request request) bool {
    text := std.http._lower(std.http.header_value(request,"content-type"))
    return text == "application/json" || text == "application/json; charset=utf-8" || text == "application/json;charset=utf-8"
}
func handle(std.http.request request, std.rest.router routes, std.database.options config) std.http.response {
    matched,route_error := std.rest.match(routes,request.method,request.path)
    if route_error.code != 0 { return problem(400,"path","invalid path") }
    if matched.status == 404 { return problem(404,"not_found","route not found") }
    if matched.status == 405 {
        allow := std.http.header { name: "Allow", value: matched.allow }
        response := problem(405,"method","method not allowed")
        response.headers = [allow]
        return response
    }
    if matched.handler_id == 1 { return std.http.response { status: 200, body: "{\"status\":\"ok\"}" } }
    query,query_error := std.rest.parse_query(request.query)
    if query_error.code != 0 { return problem(400,"query","invalid query") }
    id := 0
    if matched.handler_id >= 4 {
        parsed,valid := identifier(std.rest.param_value(matched,"id"))
        if !valid { return problem(400,"id","invalid id") }
        id = parsed
    }
    input := user_input {}
    if request.method == "POST" || request.method == "PUT" {
        if !json_content_type(request) { return problem(415,"media_type","application/json required") }
        input = parse_user(request.body)
        if !input.valid { return problem(400,"json","invalid user document") }
    }
    client,connect_error := std.mysql.connect(config)
    if connect_error.code != 0 { std.mysql.close(client*); return database_problem(connect_error) }
    answer := problem(500,"internal","operation not completed")
    if matched.handler_id == 2 {
        term := std.rest.query_value(query,"q")
        limit := 100
        raw_limit := std.rest.query_value(query,"limit")
        if raw_limit != "" {
            parsed,valid := identifier(raw_limit)
            if !valid || parsed > 100 { std.mysql.close(client*); return problem(400,"limit","limit must be 1..100") }
            limit = parsed
        }
        empty := std.database.value.text(term)
        pattern := std.database.value.text("%" + term + "%")
        maximum := std.database.value.integer(limit)
        parameters_1 := [empty,pattern,maximum];
        rows,error := repo_query(client*,"SELECT id,name,email,age FROM s_rest_users_v1 WHERE (? = '' OR name LIKE ?) ORDER BY id LIMIT ?",parameters_1)
        if error.code != 0 { answer = database_problem(error) } else {
            body := "{\"users\":["
            index := 0
            failed := false
            while index < len(rows.data) {
                item := user_json(rows.data[index])
                if item == "" { failed = true }
                if index > 0 { body = body + "," }
                body = body + item
                index = index + 1
            }
            answer = std.http.response { status: 200, body: body + "]}" }
            if failed { answer = problem(500,"data","invalid stored user") }
        }
    }
    if matched.handler_id == 3 {
        name := std.database.value.text(input.name)
        email := std.database.value.text(input.email)
        age := input.age
        parameters_2 := [name,email,age];
        result,error := repo_exec(client*,"INSERT INTO s_rest_users_v1(name,email,age) VALUES (?,?,?)",parameters_2)
        if error.code != 0 { answer = database_problem(error) } else {
            if result.affected_rows.unwrap() != "1" { answer = problem(500,"data","insert count mismatch") } else {
                generated,valid := identifier(result.last_insert_id.unwrap())
                if !valid { answer = problem(500,"data","invalid generated id") } else {
                    key := std.database.value.integer(generated)
                    parameters_3 := [key];
                    rows,read_error := repo_query(client*,"SELECT id,name,email,age FROM s_rest_users_v1 WHERE id = ?",parameters_3)
                    if read_error.code != 0 { answer = database_problem(read_error) } else {
                        if len(rows.data) != 1 { answer = problem(500,"data","inserted user missing") } else {
                            body := user_json(rows.data[0])
                            answer = std.http.response { status: 201, body: body }
                            if body == "" { answer = problem(500,"data","invalid stored user") }
                        }
                    }
                }
            }
        }
    }
    if matched.handler_id == 4 {
        key := std.database.value.integer(id)
        parameters_4 := [key];
        rows,error := repo_query(client*,"SELECT id,name,email,age FROM s_rest_users_v1 WHERE id = ?",parameters_4)
        if error.code != 0 { answer = database_problem(error) } else {
            if len(rows.data) == 0 { answer = problem(404,"not_found","user not found") } else {
                body := user_json(rows.data[0])
                answer = std.http.response { status: 200, body: body }
                if body == "" { answer = problem(500,"data","invalid stored user") }
            }
        }
    }
    if matched.handler_id == 5 || matched.handler_id == 6 {
        started := std.mysql.begin(client*)
        if started.code != 0 { answer = database_problem(started) } else {
            key := std.database.value.integer(id)
            parameters_5 := [key];
            rows,error := repo_query(client*,"SELECT id,name,email,age FROM s_rest_users_v1 WHERE id = ? FOR UPDATE",parameters_5)
            if error.code != 0 { answer = database_problem(error) } else {
                if len(rows.data) == 0 { answer = problem(404,"not_found","user not found") } else {
                    if matched.handler_id == 5 {
                        name := std.database.value.text(input.name)
                        email := std.database.value.text(input.email)
                        age := input.age
                        parameters_6 := [name,email,age,key];
                        result,write_error := repo_exec(client*,"UPDATE s_rest_users_v1 SET name=?,email=?,age=? WHERE id=?",parameters_6)
                        if write_error.code != 0 { answer = database_problem(write_error) } else {
                            parameters_7 := [key];
                            updated,read_error := repo_query(client*,"SELECT id,name,email,age FROM s_rest_users_v1 WHERE id=?",parameters_7)
                            if read_error.code != 0 { answer = database_problem(read_error) } else {
                                if len(updated.data) != 1 { answer = problem(500,"data","updated user missing") } else {
                                    body := user_json(updated.data[0])
                                    answer = std.http.response { status: 200, body: body }
                                    if body == "" { answer = problem(500,"data","invalid stored user") }
                                }
                            }
                        }
                    } else {
                        parameters_8 := [key];
                        result,write_error := repo_exec(client*,"DELETE FROM s_rest_users_v1 WHERE id=?",parameters_8)
                        if write_error.code != 0 { answer = database_problem(write_error) } else {
                            answer = std.http.response { status: 204 }
                            if result.affected_rows.unwrap() != "1" { answer = problem(500,"data","delete count mismatch") }
                        }
                    }
                }
            }
            if answer.status == 200 || answer.status == 204 {
                committed := std.mysql.commit(client*)
                if committed.code != 0 { answer = database_problem(committed) }
            } else { rolled_back := std.mysql.rollback(client*) }
        }
    }
    closed := std.mysql.close(client*)
    if closed.code != 0 { return database_problem(closed) }
    return answer
}
func main() int {
    mysql_port,mp_error := std.database.parse_integer(runtime_env_get("MYSQL_PORT","3306"))
    port,p_error := std.database.parse_integer(runtime_env_get("S_REST_PORT","8080"))
    maximum,m_error := std.database.parse_integer(runtime_env_get("S_REST_MAX_REQUESTS","0"))
    result_limit,rl_error := std.database.parse_integer(runtime_env_get("MYSQL_MAX_RESULT_BYTES","1048576"))
    if rl_error.code != 0 || result_limit < 1 || mp_error.code != 0 || p_error.code != 0 || m_error.code != 0 || maximum < 0 { println("FAIL configuration"); return 2 }
    config := std.database.options { host: runtime_env_get("MYSQL_HOST","127.0.0.1"), port: mysql_port, user: runtime_env_get("MYSQL_USER",""), password: runtime_env_get("MYSQL_PASSWORD",""), database_name: runtime_env_get("MYSQL_DATABASE",""), allow_public_key_retrieval: runtime_env_get("MYSQL_ALLOW_PUBLIC_KEY_RETRIEVAL","0") == "1", read_timeout_ms: 2000, write_timeout_ms: 2000, max_rows: 100, max_result_bytes: result_limit }
    probe,auth := std.mysql.connect(config)
    if auth.code != 0 { std.mysql.close(probe*); println("FAIL database startup"); return 3 }
    metadata,schema_error := std.mysql.exec(probe*,"CREATE TABLE IF NOT EXISTS s_rest_users_v1 (id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,name VARCHAR(200) NOT NULL,email VARCHAR(254) NOT NULL UNIQUE,age INT NULL) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin")
    version := probe.server_version
    close_error := std.mysql.close(probe*)
    if schema_error.code != 0 || close_error.code != 0 { println("FAIL isolated schema"); return 4 }
    routes := std.rest.new()
    r1,e1 := std.rest.add(routes,"GET","/health",1)
    r2,e2 := std.rest.add(r1,"GET","/api/users",2)
    r3,e3 := std.rest.add(r2,"POST","/api/users",3)
    r4,e4 := std.rest.add(r3,"GET","/api/users/:id",4)
    r5,e5 := std.rest.add(r4,"PUT","/api/users/:id",5)
    r6,e6 := std.rest.add(r5,"DELETE","/api/users/:id",6)
    if e1.code != 0 || e2.code != 0 || e3.code != 0 || e4.code != 0 || e5.code != 0 || e6.code != 0 { println("FAIL router setup"); return 5 }
    listener,listen_error := std.http.listen(std.http.options { port: port, max_body_bytes: 65536, read_timeout_ms: 500, write_timeout_ms: 500 })
    if listen_error.code != 0 { println("FAIL listen"); return 6 }
    actual,port_error := std.http.local_port(listener*)
    if port_error.code != 0 { std.http.shutdown(listener*); return 7 }
    println("READY " + std.prelude.to_string(actual) + " MYSQL " + version)
    handled := 0
    while maximum == 0 || handled < maximum {
        exchange,error := std.http.receive(listener*)
        if !exchange.closed {
            reply := problem(400,"request","request rejected")
            if error.code == 0 { reply = handle(exchange.request,r6,config) } else { reply = problem(error.status,"request","request rejected") }
            sent := std.http.respond(exchange*,reply)
            handled = handled + 1
        } else {
            if !exchange.accepted && error.code != 0 && error.code != 110 { std.http.shutdown(listener*); println("FAIL accept"); return 8 }
        }
    }
    stopped := std.http.shutdown(listener*)
    if stopped.code != 0 { return 9 }
    println("SHUTDOWN")
    return 0
}
