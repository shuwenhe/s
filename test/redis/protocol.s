package main

import (
    "std.redis"
    "std.prelude"
)

func protocol_checks() int {
    d, e := std.redis.decode("*3\r\n$-1\r\n$0\r\n\r\n*2\r\n:-9223372036854775808\r\n-ERR nested\r\n", std.redis.limits {})
    if e.code != 0 || d.count != 6 {
        return 1
    }
    if d.nodes[1].kind != "null_bulk" || d.nodes[2].kind != "bulk" || d.nodes[2].text != "" {
        return 2
    }
    if d.nodes[4].integer != -9223372036854775808 || d.nodes[5].kind != "error" || d.nodes[5].parent != 3 {
        return 3
    }

    cases := []string {
        ":9223372036854775808\r\n",
        ":-9223372036854775809\r\n",
        "$-2\r\n",
        "$-01\r\n",
        "$-0\r\n",
        "$+1\r\nx\r\n",
        "*-2\r\n",
        "$1\r\naXX",
        "+a\nb\r\n",
        ":\r\n",
        "?x\r\n",
        "$1\r\na\r",
        "*1\r\n"
    }
    i := 0
    while i < len(cases) {
        bad, err := std.redis.decode(cases[i], std.redis.limits {})
        if err.code == 0 {
            return 10 + i
        }
        i = i + 1
    }

    small, smallerr := std.redis.decode("$5\r\nhello\r\n", std.redis.limits { max_bulk_bytes: 4 })
    if smallerr.code != std.redis.error_bounds {
        return 30
    }

    deep, deepe := std.redis.decode("*1\r\n*1\r\n+OK\r\n", std.redis.limits { max_depth: 2 })
    if deepe.code != std.redis.error_bounds {
        return 31
    }

    many, manye := std.redis.decode("*2\r\n:1\r\n:2\r\n", std.redis.limits { max_array_length: 1 })
    if manye.code != std.redis.error_bounds {
        return 32
    }

    bytes := "x" + std.redis.byte_string(0) + "\r\n" + std.redis.byte_string(255)
    args := []string { "SET", "key", bytes }
    wire, we := std.redis.encode(args, std.redis.limits {})
    parsed, pe := std.redis.decode(wire, std.redis.limits {})
    if we.code != 0 || pe.code != 0 || parsed.nodes[3].text != bytes {
        return 33
    }

    stream := std.redis.new_decoder(std.redis.limits {})
    j := 0
    while j < len(wire) {
        piece := std.prelude.prelude_slice(wire, j, j + 1)
        std.redis.feed(stream*, piece)
        std.redis.advance(stream*)
        if stream.failure.code != 0 || (stream.complete && j != len(wire) - 1) {
            return 34
        }
        j = j + 1
    }
    if !stream.complete || stream.doc.nodes[3].text != bytes {
        return 35
    }

    nulls, ne := std.redis.decode("*-1\r\n", std.redis.limits {})
    empty, ee := std.redis.decode("*0\r\n", std.redis.limits {})
    if ne.code != 0 || ee.code != 0 || nulls.nodes[0].kind != "null_array" || empty.nodes[0].kind != "array" {
        return 36
    }

    trailing, te := std.redis.decode("+OK\r\n+OK\r\n", std.redis.limits {})
    if te.code != std.redis.error_protocol {
        return 37
    }

    bad_frame, bfe := std.redis.decode("+OK\r\n", std.redis.limits { max_frame_bytes: 4 })
    if bfe.code != std.redis.error_bounds {
        return 39
    }

    bad_nodes, bne := std.redis.decode("*2\r\n:1\r\n:2\r\n", std.redis.limits { max_nodes: 2 })
    if bne.code != std.redis.error_bounds {
        return 40
    }

    plus, plus_e := std.redis.decode(":+9223372036854775807\r\n", std.redis.limits {})
    if plus_e.code != 0 || plus.nodes[0].integer != 9223372036854775807 {
        return 38
    }

    println("redis protocol: PASS")
    return 0
}
