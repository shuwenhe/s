package std.redis

func new_decoder(limits config) decoder {
    c, e := _redis_limits(config)
    if e.code != 0 {
        return decoder { failure: e }
    }
    return decoder {
        config: c,
        doc: document { nodes: make([]node, c.max_nodes) },
        parents: make([]int, c.max_depth),
        remaining: make([]int, c.max_depth)
    }
}

func _redis_fail(decoder* p, int code, string message) {
    if p.failure.code == 0 {
        p.failure = error { code: code, message: message, fatal: true }
    }
}

func feed(decoder* p, string bytes) {
    if p.failure.code != 0 {
        return
    }
    if len(bytes) > p.config.max_frame_bytes + 65536 - len(p.source) {
        _redis_fail(p*, error_bounds, "RESP buffer limit")
        return
    }
    p.source = p.source + bytes
}

func _redis_number(string text) (int, error) {
    if len(text) == 0 {
        return 0, _redis_error(error_protocol, "empty RESP integer")
    }
    negative := __host_byte_at(text, 0) == 45
    i := 0
    limit := -9223372036854775807
    if negative {
        i = 1
        limit = -9223372036854775808
    }
    if __host_byte_at(text, 0) == 43 {
        i = 1
    }
    if i == len(text) {
        return 0, _redis_error(error_protocol, "missing RESP integer digits")
    }
    n := 0
    while i < len(text) {
        d := __host_byte_at(text, i) - 48
        if d < 0 || d > 9 {
            return 0, _redis_error(error_protocol, "invalid RESP integer")
        }
        if n < limit / 10 {
            return 0, _redis_error(error_protocol, "RESP integer overflow")
        }
        n = n * 10
        if n < limit + d {
            return 0, _redis_error(error_protocol, "RESP integer overflow")
        }
        n = n - d
        i = i + 1
    }
    if !negative {
        n = 0 - n
    }
    return n, error {}
}

func _redis_settle(decoder* p) {
    while p.depth > 0 && p.remaining[p.depth - 1] == 0 {
        p.depth = p.depth - 1
    }
    if p.depth == 0 {
        p.complete = true
    }
}

func _redis_node(decoder* p, string kind, string text, int number, int length) int {
    if p.doc.count >= p.config.max_nodes {
        _redis_fail(p*, error_bounds, "RESP node limit")
        return -1
    }
    if p.depth + 1 > p.config.max_depth {
        _redis_fail(p*, error_bounds, "RESP depth limit")
        return -1
    }
    parent := -1
    if p.depth > 0 {
        parent = p.parents[p.depth - 1]
        p.remaining[p.depth - 1] = p.remaining[p.depth - 1] - 1
    }
    index := p.doc.count
    p.doc.nodes[index] = node { kind: kind, text: text, integer: number, parent: parent, length: length }
    p.doc.count = index + 1
    return index
}

func advance(decoder* p) {
    while !p.complete && p.failure.code == 0 {
        if p.waiting_bulk {
            if p.bulk_length > p.config.max_frame_bytes - p.position - 2 {
                _redis_fail(p*, error_bounds, "RESP frame limit")
                return
            }
            if len(p.source) - p.position < p.bulk_length + 2 {
                return
            }
            end := p.position + p.bulk_length
            if __host_byte_at(p.source, end) != 13 || __host_byte_at(p.source, end + 1) != 10 {
                _redis_fail(p*, error_protocol, "invalid bulk terminator")
                return
            }
            p.doc.nodes[p.bulk_node].text = __string_slice(p.source, p.position, end)
            p.position = end + 2
            p.scan = p.position
            p.waiting_bulk = false
            _redis_settle(p*)
        } else {
            if p.position >= p.config.max_frame_bytes {
                _redis_fail(p*, error_bounds, "RESP frame limit")
                return
            }
            if p.position >= len(p.source) {
                return
            }
            start := p.position
            if p.scan <= start {
                p.scan = start + 1
            }
            found := false
            while p.scan < len(p.source) {
                if p.scan >= p.config.max_frame_bytes {
                    _redis_fail(p*, error_bounds, "RESP frame limit")
                    return
                }
                b := __host_byte_at(p.source, p.scan)
                if b == 10 {
                    _redis_fail(p*, error_protocol, "bare LF in RESP header")
                    return
                }
                if b == 13 {
                    if p.scan + 1 >= len(p.source) {
                        return
                    }
                    if __host_byte_at(p.source, p.scan + 1) != 10 {
                        _redis_fail(p*, error_protocol, "invalid RESP CRLF")
                        return
                    }
                    found = true
                    break
                }
                p.scan = p.scan + 1
            }
            if !found {
                return
            }
            if p.scan + 2 > p.config.max_frame_bytes {
                _redis_fail(p*, error_bounds, "RESP frame limit")
                return
            }
            tag := __host_byte_at(p.source, start)
            text := __string_slice(p.source, start + 1, p.scan)
            p.position = p.scan + 2
            p.scan = p.position
            if tag == 43 || tag == 45 {
                kind := "simple"
                if tag == 45 {
                    kind = "error"
                }
                _redis_node(p*, kind, text, 0, 0)
                _redis_settle(p*)
            } else {
                if tag != 58 && tag != 36 && tag != 42 {
                    _redis_fail(p*, error_protocol, "unknown RESP type")
                    return
                }
                if tag != 58 &&
                    len(text) > 0 &&
                    ((__host_byte_at(text, 0) == 45 && text != "-1") || __host_byte_at(text, 0) == 43) {
                    _redis_fail(p*, error_protocol, "invalid RESP length sign")
                    return
                }
                number, err := _redis_number(text)
                if err.code != 0 {
                    _redis_fail(p*, err.code, err.message)
                    return
                }
                if tag == 58 {
                    _redis_node(p*, "integer", "", number, 0)
                    _redis_settle(p*)
                } else {
                    if number < -1 {
                        _redis_fail(p*, error_protocol, "invalid RESP length")
                        return
                    }
                    if number == -1 {
                        kind := "null_bulk"
                        if tag == 42 {
                            kind = "null_array"
                        }
                        _redis_node(p*, kind, "", 0, 0)
                        _redis_settle(p*)
                    } else {
                        if tag == 36 {
                            if number > p.config.max_bulk_bytes {
                                _redis_fail(p*, error_bounds, "RESP bulk limit")
                                return
                            }
                            index := _redis_node(p*, "bulk", "", 0, number)
                            if index < 0 {
                                return
                            }
                            p.bulk_node = index
                            p.bulk_length = number
                            p.waiting_bulk = true
                        } else {
                            if number > p.config.max_array_length ||
                                number > p.config.max_nodes - p.doc.count - 1 {
                                _redis_fail(p*, error_bounds, "RESP array limit")
                                return
                            }
                            index := _redis_node(p*, "array", "", 0, number)
                            if index < 0 {
                                return
                            }
                            if number == 0 {
                                _redis_settle(p*)
                            } else {
                                p.parents[p.depth] = index
                                p.remaining[p.depth] = number
                                p.depth = p.depth + 1
                            }
                        }
                    }
                }
            }
        }
    }
}

func decode(string wire, limits config) (document, error) {
    p := new_decoder(config)
    feed(p*, wire)
    advance(p*)
    if p.failure.code != 0 {
        return p.doc, p.failure
    }
    if !p.complete {
        return p.doc, _redis_error(error_protocol, "truncated RESP frame")
    }
    if p.position != len(wire) {
        return p.doc, _redis_error(error_protocol, "trailing RESP bytes")
    }
    return p.doc, error {}
}

func _redis_encode_range(string[] args, int start, int end) string {
    if start == end {
        return ""
    }
    if end - start == 1 {
        return "$" + std.prelude.to_string(len(args[start])) + "\r\n" + args[start] + "\r\n"
    }
    mid := start + (end - start) / 2
    return _redis_encode_range(args, start, mid) + _redis_encode_range(args, mid, end)
}

func encode(string[] args, limits config) (string, error) {
    c, e := _redis_limits(config)
    if e.code != 0 {
        return "", e
    }
    if len(args) == 0 || len(args) > c.max_array_length {
        return "", _redis_error(error_bounds, "invalid command argument count")
    }
    size := 1 + len(std.prelude.to_string(len(args))) + 2
    i := 0
    while i < len(args) {
        n := len(args[i])
        if n > c.max_bulk_bytes {
            return "", _redis_error(error_bounds, "command bulk limit")
        }
        overhead := 5 + len(std.prelude.to_string(n))
        if n > c.max_frame_bytes - size - overhead {
            return "", _redis_error(error_bounds, "command frame limit")
        }
        size = size + n + overhead
        i = i + 1
    }
    return "*" + std.prelude.to_string(len(args)) + "\r\n" + _redis_encode_range(args, 0, len(args)), error {}
}
