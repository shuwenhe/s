func test_parse_ip_port() bool {
    ip, port = parse_ip_port("127.0.0.1:12345")
    ip == "127.0.0.1" && port == 12345
}

func test_split_host_port() bool {
    host, port = split_host_port("localhost:80")
    host == "localhost" && port == "80"
}

func test_error_types() bool {
    e1 = parse_error { typ: "ip", text: "bad" }
    e2 = addr_error { err: "fail", addr: "x" }
    e3 = unknown_network_error { net: "foo" }
    e4 = timeout_error {}
    e5 = op_error { op: "read", net: "tcp", source nil, addr nil, err: "fail" }
    e1.error() != "" && e2.error() != "" && e3.error() != "" && e4.error() != "" && e5.error() != ""
}

func test_tcp_listen_accept() bool {
    listener l = listen("tcp", "127.0.0.1:18080")
    if l == nil {
        return false
    }
    conn c = l.accept()
    l.close()
    true
}

func test_udp_listen() bool {
    listener l = listen("udp", "127.0.0.1:19090")
    if l == nil {
        return false
    }
    l.close()
    true
}
package src.net

func test_tcp_addr_string() bool {
    tcp_addr addr = tcp_addr { ip: "127.0.0.1", port 8080 }
    return addr.string() == "127.0.0.1:8080"
}

func test_udp_addr_string() bool {
    udp_addr addr = udp_addr { ip: "127.0.0.1", port 9000 }
    return addr.string() == "127.0.0.1:9000"
}

func test_tcpconn_methods() bool {
    tcp_conn c = tcp_conn { fd: 1, laddr tcp_addr { ip: "127.0.0.1", port 8080 }, raddr tcp_addr { ip: "127.0.0.1", port 9001 } }
    c.local_addr().string() == "127.0.0.1:8080" && c.remote_addr().string() == "127.0.0.1:9001"
}

func test_udpconn_methods() bool {
    udp_conn c = udp_conn { fd: 2, laddr udp_addr { ip: "127.0.0.1", port 9000 }, raddr udp_addr { ip: "127.0.0.1", port 9002 } }
    c.local_addr().string() == "127.0.0.1:9000" && c.remote_addr().string() == "127.0.0.1:9002"
}

func test_tcplistener_methods() bool {
    tcp_listener l = tcp_listener { fd: 3, laddr tcp_addr { ip: "0.0.0.0", port 8080 } }
    l.addr().string() == "0.0.0.0:8080"
}

func test_udplistener_methods() bool {
    udp_listener l = udp_listener { fd: 4, laddr udp_addr { ip: "0.0.0.0", port 9000 } }
    l.addr().string() == "0.0.0.0:9000"
}
