package main

import "std.redis"

func tls_checks() int {
    config, config_error := redis_test_options()
    if config_error != 0 {
        return config_error
    }
    if !config.use_tls {
        println("TLS test requires REDIS_TLS=1")
        return 92
    }

    config.tls_server_name = "wrong.local"
    wrong, wrong_error := std.redis.connect(config)
    if wrong_error.code == 0 || !wrong.closed {
        std.redis.close(wrong*)
        return 90
    }

    config.tls_server_name = "redis.local"
    config.tls_ca_file = runtime_env_get("REDIS_TLS_WRONG_CA_FILE", "")
    if config.tls_ca_file == "" {
        println("TLS test requires REDIS_TLS_WRONG_CA_FILE")
        return 93
    }

    untrusted, untrusted_error := std.redis.connect(config)
    if untrusted_error.code == 0 || !untrusted.closed {
        std.redis.close(untrusted*)
        return 91
    }

    println("redis TLS certificate and hostname rejection: PASS")
    return 0
}
