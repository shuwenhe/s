package main

import "std.redis"

func fault_checks() int {
    config, config_error := redis_test_options()
    if config_error != 0 {
        return config_error
    }
    config.password = ""
    config.use_tls = false
    config.read_timeout_ms = 200

    name := runtime_env_get("S_REDIS_FAULT", "")
    expected := -1
    if name == "fragmented" {
        expected = 0
    }
    if name == "malformed" || name == "wrongtype" {
        expected = std.redis.error_protocol
    }
    if name == "oversized" {
        expected = std.redis.error_bounds
    }
    if name == "truncated" || name == "disconnect" {
        expected = std.redis.error_transport
    }
    if name == "timeout" || name == "trickle" {
        expected = std.redis.error_timeout
    }
    if name == "servererror" {
        expected = std.redis.error_server
    }
    if expected < 0 {
        println("unknown S_REDIS_FAULT case")
        return 80
    }

    c, e := std.redis.connect(config)
    if e.code != 0 {
        return 81
    }

    result := std.redis.ping(c*)
    status := 0
    if result.code != expected {
        status = 82
    }
    if result.code != 0 && result.code != std.redis.error_server && !c.closed {
        status = 83
    }
    if result.code == std.redis.error_server && c.closed {
        status = 84
    }

    std.redis.close(c*)
    if std.redis.close(c*).code != 0 {
        return 85
    }
    if status != 0 {
        return status
    }

    println("redis fault " + name + ": PASS")
    return 0
}
