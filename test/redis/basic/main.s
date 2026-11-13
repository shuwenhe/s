package main

import (
    "std.redis"
    "std.string"
    "std.time"
    "std.prelude"
)

extern "intrinsic" func runtime_env_get(string key, string fallback) string

// Optional smoke test for an existing local Redis. Uses a unique key and removes it.
func main() int {
    port, pe := std.string.parse_int(runtime_env_get("REDIS_PORT", "6379"))
    if pe.code != 0 {
        println("invalid REDIS_PORT")
        return 1
    }

    config := std.redis.options {
        host: runtime_env_get("REDIS_HOST", "127.0.0.1"),
        port: port,
        username: runtime_env_get("REDIS_USER", ""),
        password: runtime_env_get("REDIS_PASSWORD", ""),
        use_tls: runtime_env_get("REDIS_TLS", "0") == "1",
        tls_server_name: runtime_env_get("REDIS_TLS_SERVER_NAME", ""),
        tls_ca_file: runtime_env_get("REDIS_TLS_CA_FILE", "")
    }
    c, e := std.redis.connect(config)
    if e.code != 0 {
        println("Redis connection failed")
        return 2
    }

    status := smoke(c*)
    std.redis.close(c*)
    if status != 0 {
        println("Redis smoke test failed")
        return status
    }

    println("native S Redis: PING, binary SET/GET, DEL: PASS")
    return 0
}

func smoke(std.redis.connection* c) int {
    if std.redis.ping(c*).code != 0 {
        return 3
    }

    now, te := std.time.monotonic_clock()
    if te.code != 0 {
        return 4
    }

    key := "s:redis:smoke:" + std.prelude.to_string(now)
    value := "S Redis\r\n" + std.redis.byte_string(0) + std.redis.byte_string(255)
    config := std.redis.set_options { ex_seconds: 60, nx: true }
    written, we := std.redis.set(c*, key, value, config)
    if we.code != 0 || !written {
        return 5
    }

    got, ge := std.redis.get(c*, key)
    deleted, de := std.redis.del(c*, key)
    if ge.code != 0 || !got.present || got.value != value || de.code != 0 || deleted != 1 {
        return 6
    }

    return 0
}
