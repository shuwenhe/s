package main

import (
    "std.redis"
    "std.string"
)

extern "intrinsic" func runtime_env_get(string key, string fallback) string

// Process creation stays with the build tool until std.process supports it.
// All test behavior, Redis requests, assertions and fault peers are native S.
func main() int {
    mode := runtime_env_get("S_REDIS_TEST", "protocol")
    if mode == "protocol" {
        return protocol_checks()
    }
    if mode == "integration" {
        return integration_checks()
    }
    if mode == "tls" {
        result := integration_checks()
        if result != 0 {
            return result
        }
        return tls_checks()
    }
    if mode == "fault" {
        return fault_checks()
    }

    println("unknown S_REDIS_TEST mode")
    return 100
}

func redis_test_options() (std.redis.options, int) {
    port, port_error := std.string.parse_int(runtime_env_get("REDIS_PORT", "6379"))
    if port_error.code != 0 || port < 1 || port > 65535 {
        println("invalid REDIS_PORT")
        return std.redis.options {}, 101
    }

    config := std.redis.options {
        host: "127.0.0.1",
        port: port,
        password: "local-test-secret",
        read_timeout_ms: 1000,
        write_timeout_ms: 1000,
        connect_timeout_ms: 1000,
        use_tls: runtime_env_get("REDIS_TLS", "0") == "1",
        tls_server_name: runtime_env_get("REDIS_TLS_SERVER_NAME", "redis.local"),
        tls_ca_file: runtime_env_get("REDIS_TLS_CA_FILE", "")
    }
    return config, 0
}
