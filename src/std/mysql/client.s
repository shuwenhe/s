package std.mysql
import ("std.database"; "std.crypto"; "std.tcp"; "std.tls")

func _has_nul(string text) bool {
    index := 0
    while index < len(text) {
        if std.database._byte(text,index) == 0 { return true }
        index = index + 1
    }
    return false
}
func _validate_options(std.database.options config) (std.database.options,std.database.error) {
    if config.host == "" || config.host == "localhost" { config.host = "127.0.0.1" }
    if config.port == 0 { config.port = 3306 }
    if config.connect_timeout_ms == 0 { config.connect_timeout_ms = 5000 }
    if config.read_timeout_ms == 0 { config.read_timeout_ms = 5000 }
    if config.write_timeout_ms == 0 { config.write_timeout_ms = 5000 }
    if config.max_packet_bytes == 0 { config.max_packet_bytes = 16777214 }
    if config.max_result_bytes == 0 { config.max_result_bytes = 16777214 }
    if config.max_rows == 0 { config.max_rows = 100000 }
    if config.port < 1 || config.port > 65535 || config.connect_timeout_ms < 1 || config.connect_timeout_ms > 2147483647 || config.read_timeout_ms < 1 || config.read_timeout_ms > 2147483647 || config.write_timeout_ms < 1 || config.write_timeout_ms > 2147483647 || config.max_packet_bytes < 1024 || config.max_packet_bytes > 16777214 || config.max_result_bytes < 1 || config.max_result_bytes > 1073741824 || config.max_rows < 1 || config.max_rows > 1000000 {
        return config,std.database.failure(std.database.error_invalid,"invalid MySQL connection limits")
    }
    if len(config.user) == 0 || len(config.user) > 256 || len(config.database_name) > 256 || len(config.password) > 4096 || _has_nul(config.user) || _has_nul(config.database_name) || _has_nul(config.password) {
        return config,std.database.failure(std.database.error_invalid,"invalid MySQL credentials or database name")
    }
    if config.tls_ca_file != "" && config.tls_server_name == "" { return config,std.database.failure(std.database.error_invalid,"TLS CA requires tls_server_name") }
    return config,std.database.error {}
}
func connect(std.database.options requested) (connection,std.database.error) {
    config,validation := _validate_options(requested)
    client := connection { closed: true, secure: std.tls.session { closed: true }, config: config }
    if validation.code != 0 { return client,validation }
    identity,entropy_error := std.crypto.random_bytes(16)
    if entropy_error.code != 0 { return client,std.database.failure(std.database.error_authentication,"OS entropy unavailable") }
    client.identity = identity
    socket,network_error := std.tcp.dial_ipv4(config.host,config.port,config.connect_timeout_ms)
    if network_error.code != 0 { return client,std.database.error { code: std.database.error_transport, native_code: network_error.code, driver: "mysql", message: "MySQL connect failed", fatal: true } }
    client.socket = socket
    client.closed = false
    deadline_error := _start_deadline(client*,config.connect_timeout_ms)
    if deadline_error.code != 0 { return client,deadline_error }
    greeting,read_error := _read_packet(client*)
    if read_error.code != 0 { return client,read_error }
    if len(greeting) > 0 && std.database._byte(greeting,0) == 255 {
        problem := decode_error(greeting)
        fatal_error := _fatal(client*,problem); return client,fatal_error
    }
    hello,handshake_error := decode_handshake(greeting)
    if handshake_error.code != 0 { fatal_error := _fatal(client*,handshake_error); return client,fatal_error }
    client.server_connection_id = hello.connection_id
    client.server_version = hello.server_version
    flags := 512 | 32768 | 524288 | 8192 | 1
    if config.database_name != "" { flags = flags | 8 }
    if (hello.capabilities & flags) != flags { fatal_error := _transport_error(client*,0,"required MySQL capabilities unavailable"); return client,fatal_error }
    if config.tls_server_name != "" {
        if (hello.capabilities & 2048) == 0 { fatal_error := _transport_error(client*,0,"MySQL server does not offer TLS"); return client,fatal_error }
        flags = flags | 2048
    }
    prefix := _u(flags,4) + _u(config.max_packet_bytes,4) + _u(45,1) + _zeroes(23)
    if config.tls_server_name != "" {
        sent := _write_packet(client*,prefix)
        if sent.code != 0 { connection_error := _fatal(client*,sent); return client,connection_error }
        remaining := _remaining(client.deadline,config.connect_timeout_ms)
        if remaining == 0 { fatal_error := _transport_error(client*,110,"MySQL TLS handshake timeout"); return client,fatal_error }
        secure,tls_error := std.tls.connect(socket,config.tls_server_name,config.tls_ca_file,remaining)
        if tls_error.code != 0 { fatal_error := _transport_error(client*,tls_error.code,"MySQL TLS handshake or certificate validation failed"); return client,fatal_error }
        client.secure = secure
        client.encrypted = true
    }
    plugin := hello.auth_plugin
    scramble := hello.scramble
    token,auth_error := auth_response(plugin,config.password,scramble)
    if auth_error.code != 0 { fatal_error := _fatal(client*,auth_error); return client,fatal_error }
    response := prefix + config.user + _u(0,1) + _u(len(token),1) + token
    if config.database_name != "" { response = response + config.database_name + _u(0,1) }
    response = response + plugin + _u(0,1)
    sent := _write_packet(client*,response)
    if sent.code != 0 { connection_error := _fatal(client*,sent); return client,connection_error }
    step := 0
    while step < 8 {
        incoming,problem := _read_packet(client*)
        if problem.code != 0 { return client,problem }
        if len(incoming) == 0 { fatal_error := _transport_error(client*,0,"empty authentication response"); return client,fatal_error }
        header := std.database._byte(incoming,0)
        if header == 0 {
            ok,ok_error := decode_ok(incoming)
            if ok_error.code != 0 { fatal_error := _fatal(client*,ok_error); return client,fatal_error }
            return client,std.database.error {}
        }
        if header == 255 {
            failure := decode_error(incoming)
            fatal_error := _fatal(client*,failure); return client,fatal_error
        }
        outgoing := ""
        if header == 254 {
            switched,switch_error := decode_auth_switch(incoming)
            if switch_error.code != 0 { fatal_error := _fatal(client*,switch_error); return client,fatal_error }
            plugin = switched.plugin
            scramble = switched.scramble
            switched_token,token_error := auth_response(plugin,config.password,scramble)
            if token_error.code != 0 { fatal_error := _fatal(client*,token_error); return client,fatal_error }
            outgoing = switched_token
        } else {
            if plugin != "caching_sha2_password" || len(incoming) != 2 || header != 1 { fatal_error := _transport_error(client*,0,"unexpected MySQL authentication response"); return client,fatal_error }
            status := std.database._byte(incoming,1)
            if status == 3 { step = step + 1; continue }
            if status != 4 { fatal_error := _transport_error(client*,0,"invalid SHA2 authentication status"); return client,fatal_error }
            if client.encrypted { outgoing = config.password + _u(0,1) } else {
                public_key := config.server_public_key
                if public_key == "" {
                    if !config.allow_public_key_retrieval {
                        failure := std.database.failure(std.database.error_authentication,"SHA2 full authentication requires TLS, a pinned server_public_key or explicit allow_public_key_retrieval")
                        fatal_error := _fatal(client*,failure); return client,fatal_error
                    }
                    request := _u(2,1)
                    requested_key := _write_packet(client*,request)
                    if requested_key.code != 0 { connection_error := _fatal(client*,requested_key); return client,connection_error }
                    key_packet,key_error := _read_packet(client*)
                    if key_error.code != 0 { return client,key_error }
                    if len(key_packet) < 2 || std.database._byte(key_packet,0) != 1 { fatal_error := _transport_error(client*,0,"invalid server RSA key response"); return client,fatal_error }
                    public_key = std.database._slice(key_packet,1,len(key_packet))
                    if std.database._byte(public_key,len(public_key) - 1) == 0 { public_key = std.database._slice(public_key,0,len(public_key) - 1) }
                }
                encrypted,rsa_error := rsa_password(config.password,scramble,public_key)
                if rsa_error.code != 0 { fatal_error := _fatal(client*,rsa_error); return client,fatal_error }
                outgoing = encrypted
            }
        }
        written := _write_packet(client*,outgoing)
        if written.code != 0 { connection_error := _fatal(client*,written); return client,connection_error }
        step = step + 1
    }
    fatal_error := _transport_error(client*,0,"too many authentication exchanges"); return client,fatal_error
}
func ping(connection* client) std.database.error {
    payload := _u(14,1)
    problem := _command(client*,payload)
    if problem.code != 0 { return problem }
    incoming,error := _read_packet(client*)
    if error.code != 0 { return error }
    if len(incoming) > 0 && std.database._byte(incoming,0) == 255 { return _server_error(client*,incoming) }
    ok,ok_error := decode_ok(incoming)
    if ok_error.code != 0 { return _fatal(client*,ok_error) }
    return std.database.error {}
}
func close(connection* client) std.database.error {
    if client.closed { return std.database.error {} }
    quit := _u(1,1)
    problem := _command(client*,quit)
    _abort(client*)
    return problem
}
