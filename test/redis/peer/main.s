package main

import (
    "std.tcp"
    "std.time"
    "std.prelude"
)

extern "intrinsic" func runtime_env_get(string key, string fallback) string

func main() int {
    listener, listen_error := std.tcp.listen_ipv4("127.0.0.1", 0, 1)
    if listen_error.code != 0 {
        return 1
    }

    port, port_error := std.tcp.local_port(listener)
    if port_error.code != 0 {
        std.tcp.close(listener*)
        return 2
    }
    println("READY " + std.prelude.to_string(port))

    if runtime_env_get("S_REDIS_PEER_MODE", "") == "port" {
        std.tcp.close(listener*)
        return 0
    }

    c, accept_error := std.tcp.accept(listener, 5000)
    std.tcp.close(listener*)
    if accept_error.code != 0 {
        return 3
    }

    result := serve(c*)
    std.tcp.close(c*)
    return result
}

func serve(std.tcp.socket* c) int {
    request := ""
    while len(request) < 14 {
        maximum := 14 - len(request)
        chunk, e := std.tcp.read_some(c*, maximum, 1000)
        if e.code != 0 || chunk.eof {
            return 4
        }
        request = request + chunk.data
    }
    if request != "*1\r\n$4\r\nPING\r\n" {
        return 5
    }

    name := runtime_env_get("S_REDIS_FAULT", "")
    if name == "disconnect" {
        return 0
    }
    if name == "timeout" {
        if std.time.sleep_ms(400).code != 0 {
            return 6
        }
        return expect_closed(c*)
    }

    payload := "+PONG\r\n"
    if name == "malformed" {
        payload = "$1\r\nxZZ"
    }
    if name == "oversized" {
        payload = "$1048577\r\n"
    }
    if name == "truncated" {
        payload = "$5\r\nxy"
    }
    if name == "wrongtype" {
        payload = ":1\r\n"
    }
    if name == "servererror" {
        payload = "-ERR deliberate\r\n"
    }

    if name == "fragmented" || name == "trickle" {
        pause := 2
        if name == "trickle" {
            pause = 60
        }
        i := 0
        while i < len(payload) {
            piece := std.prelude.prelude_slice(payload, i, i + 1)
            written, e := std.tcp.write_all(c*, piece, 1000)
            if e.code != 0 {
                if name == "trickle" {
                    return expect_closed(c*)
                }
                return 7
            }
            if written != 1 || std.time.sleep_ms(pause).code != 0 {
                return 8
            }
            i = i + 1
        }
    } else {
        written, e := std.tcp.write_all(c*, payload, 1000)
        if e.code != 0 || written != len(payload) {
            return 9
        }
    }

    if name == "truncated" {
        return 0
    }
    return expect_closed(c*)
}

func expect_closed(std.tcp.socket* c) int {
    chunk, e := std.tcp.read_some(c*, 1, 1000)
    if e.code != 0 || !chunk.eof {
        return 10
    }
    return 0
}
