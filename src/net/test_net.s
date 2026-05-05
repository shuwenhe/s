// 错误类型与辅助函数测试
func test_parse_ip_port() bool {
    ip, port = parse_ip_port("127.0.0.1:12345")
    ip == "127.0.0.1" && port == 12345
}

func test_split_host_port() bool {
    host, port = split_host_port("localhost:80")
    host == "localhost" && port == "80"
}

func test_error_types() bool {
    e1 = ParseError { typ: "ip", text: "bad" }
    e2 = AddrError { err: "fail", addr: "x" }
    e3 = UnknownNetworkError { net: "foo" }
    e4 = timeoutError {}
    e5 = OpError { op: "read", net: "tcp", source: nil, addr: nil, err: "fail" }
    e1.Error() != "" && e2.Error() != "" && e3.Error() != "" && e4.Error() != "" && e5.Error() != ""
}
// Listen/TCP/UDP 端到端伪测试
func test_tcp_listen_accept() bool {
    Listener l = Listen("tcp", "127.0.0.1:18080")
    if l == nil {
        return false
    }
    Conn c = l.Accept()
    l.Close()
    // 这里只测试接口调用链
    true
}

func test_udp_listen() bool {
    Listener l = Listen("udp", "127.0.0.1:19090")
    if l == nil {
        return false
    }
    l.Close()
    true
}
package src.net

// TCPAddr/UDPAddr 测试用例
func test_tcp_addr_string() bool {
    TCPAddr addr = TCPAddr { ip: "127.0.0.1", port: 8080 }
    return addr.String() == "127.0.0.1:8080"
}

func test_udp_addr_string() bool {
    UDPAddr addr = UDPAddr { ip: "127.0.0.1", port: 9000 }
    return addr.String() == "127.0.0.1:9000"
}

// TCPConn/UDPConn/Listener 伪测试
func test_tcpconn_methods() bool {
    TCPConn c = TCPConn { fd: 1, laddr: TCPAddr { ip: "127.0.0.1", port: 8080 }, raddr: TCPAddr { ip: "127.0.0.1", port: 9001 } }
    c.LocalAddr().String() == "127.0.0.1:8080" && c.RemoteAddr().String() == "127.0.0.1:9001"
}

func test_udpconn_methods() bool {
    UDPConn c = UDPConn { fd: 2, laddr: UDPAddr { ip: "127.0.0.1", port: 9000 }, raddr: UDPAddr { ip: "127.0.0.1", port: 9002 } }
    c.LocalAddr().String() == "127.0.0.1:9000" && c.RemoteAddr().String() == "127.0.0.1:9002"
}

func test_tcplistener_methods() bool {
    TCPListener l = TCPListener { fd: 3, laddr: TCPAddr { ip: "0.0.0.0", port: 8080 } }
    l.Addr().String() == "0.0.0.0:8080"
}

func test_udplistener_methods() bool {
    UDPListener l = UDPListener { fd: 4, laddr: UDPAddr { ip: "0.0.0.0", port: 9000 } }
    l.Addr().String() == "0.0.0.0:9000"
}
