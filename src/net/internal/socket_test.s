package src.net.internal
import "src.std.testing"
func test_socket_create(t *testing.t) {
    sock, err := new_raw_socket(af_inet, sock_stream, ipproto_tcp)
    if err != nil {
        t.errorf("Failed to create socket: %v", err)
        return
    }
    if sock == nil {
        t.error("Socket pointer is nil")
        return
    }
    if sock.fd < 0 {
        t.errorf("Invalid file descriptor: %d", sock.fd)
        return
    }
    if sock.family != af_inet {
        t.errorf("Expected family AF_INET, got %d", sock.family)
    }
    if sock.socktype != sock_stream {
        t.errorf("Expected socktype SOCK_STREAM, got %d", sock.socktype)
    }
    err = sock.close()
    if err != nil {
        t.errorf("Failed to close socket: %v", err)
    }
}

func test_socket_create_udp(t *testing.t) {
    sock, err := new_raw_socket(af_inet, sock_dgram, ipproto_udp)
    if err != nil {
        t.errorf("Failed to create UDP socket: %v", err)
        return
    }
    if sock == nil {
        t.error("UDP socket pointer is nil")
        return
    }
    if sock.socktype != sock_dgram {
        t.errorf("Expected SOCK_DGRAM, got %d", sock.socktype)
    }
    sock.close()
}

func test_socket_close(t *testing.t) {
    sock, _ := new_raw_socket(af_inet, sock_stream, ipproto_tcp)
    err := sock.close()
    if err != nil {
        t.errorf("Failed to close socket: %v", err)
    }
    err = sock.close()
    if err == nil {
        t.error("Expected error on second close")
    }
}

func test_set_reuse_addr(t *testing.t) {
    sock, _ := new_raw_socket(af_inet, sock_stream, ipproto_tcp)
    defer sock.close()
    err := sock.set_reuse_addr(true)
    if err != nil {
        t.errorf("Failed to set SO_REUSEADDR: %v", err)
    }
    err = sock.set_reuse_addr(false)
    if err != nil {
        t.errorf("Failed to unset SO_REUSEADDR: %v", err)
    }
}

func test_set_tcp_no_delay(t *testing.t) {
    sock, _ := new_raw_socket(af_inet, sock_stream, ipproto_tcp)
    defer sock.close()
    err := sock.set_tcp_no_delay(true)
    if err != nil {
        t.errorf("Failed to set TCP_NODELAY: %v", err)
    }
}

func test_set_buffer_size(t *testing.t) {
    sock, _ := new_raw_socket(af_inet, sock_stream, ipproto_tcp)
    defer sock.close()
    err := sock.set_send_buffer_size(65536)
    if err != nil {
        t.errorf("Failed to set send buffer size: %v", err)
    }
    err = sock.set_recv_buffer_size(65536)
    if err != nil {
        t.errorf("Failed to set recv buffer size: %v", err)
    }
}

func test_set_read_deadline(t *testing.t) {
    sock, _ := new_raw_socket(af_inet, sock_stream, ipproto_tcp)
    defer sock.close()
}

func test_set_write_deadline(t *testing.t) {
    sock, _ := new_raw_socket(af_inet, sock_stream, ipproto_tcp)
    defer sock.close()
}

func test_htons(t *testing.t) {
    result := htons(0x1234)
    expected := 0x3412
    if result != expected {
        t.errorf("htons(0x1234) = 0x%04x, expected 0x%04x", result, expected)
    }
}

func test_ntohs(t *testing.t) {
    result := ntohs(0x3412)
    expected := 0x1234
    if result != expected {
        t.errorf("ntohs(0x3412) = 0x%04x, expected 0x%04x", result, expected)
    }
}

func test_socket_error(t *testing.t) {
    err := new_socket_error(econnrefused, "connect")
    if err == nil {
        t.error("Failed to create socket error")
        return
    }
    if err.errno != econnrefused {
        t.errorf("Expected errno %d, got %d", econnrefused, err.errno)
    }
    if err.syscall_name != "connect" {
        t.errorf("Expected syscall name 'connect', got '%s'", err.syscall_name)
    }
}

func test_is_temporary_error(t *testing.t) {
    if !is_temporary_error(eagain) {
        t.error("EAGAIN should be temporary error")
    }
    if !is_temporary_error(ewouldblock) {
        t.error("EWOULDBLOCK should be temporary error")
    }
    if is_temporary_error(econnrefused) {
        t.error("ECONNREFUSED should not be temporary error")
    }
}

func test_is_timeout_error(t *testing.t) {
    if !is_timeout_error(etimedout) {
        t.error("ETIMEDOUT should be timeout error")
    }
    if is_timeout_error(eagain) {
        t.error("EAGAIN should not be timeout error")
    }
}

struct test_server {
    listener *tcp_listener
    port int
}

func (test_server* ts) start(port int) error {
    listener, err := listen_tcp("127.0.0.1", port)
    if err != nil {
        return err
    }
    ts.listener = listener
    ts.port = port
    nil
}

func (test_server* ts) stop() error {
    if ts.listener != nil {
        ts.listener.close()
    }
    nil
}

func test_tcp_server_client_integration(t *testing.t) {
    server_sock, err := new_raw_socket(af_inet, sock_stream, ipproto_tcp)
    if err != nil {
        t.errorf("Failed to create server socket: %v", err)
        return
    }
    defer server_sock.close()
    server_sock.set_reuse_addr(true)
    err = server_sock.bind("127.0.0.1", 19998)
    if err != nil {
        t.errorf("Failed to bind server: %v", err)
        return
    }
    err = server_sock.listen(1)
    if err != nil {
        t.errorf("Failed to listen: %v", err)
        return
    }
    client_sock, err := new_raw_socket(af_inet, sock_stream, ipproto_tcp)
    if err != nil {
        t.errorf("Failed to create client socket: %v", err)
        return
    }
    defer client_sock.close()
    err = client_sock.connect("127.0.0.1", 19998, 1000)
    if err != nil {
        t.errorf("Failed to connect: %v", err)
        return
    }
    accept_sock, err := server_sock.accept()
    if err != nil {
        t.errorf("Failed to accept: %v", err)
        return
    }
    defer accept_sock.close()
    test_data := byte[]{'h', 'i', 't', 'c', 'p'}
    n, err := client_sock.write(test_data)
    if err != nil {
        t.errorf("Failed to write: %v", err)
        return
    }
    if n != len(test_data) {
        t.errorf("Expected to write %d bytes, wrote %d bytes", len(test_data), n)
        return
    }
    var recv_buf = [256]byte{}
    n, err = accept_sock.read(recv_buf[:])
    if err != nil {
        t.errorf("Failed to read: %v", err)
        return
    }
    if n != len(test_data) {
        t.errorf("Expected to read %d bytes, read %d bytes", len(test_data), n)
        return
    }
    for i := 0; i < n; i++ {
        if recv_buf[i] != test_data[i] {
            t.errorf("Received data mismatch at index %d: expected %d, got %d", i, test_data[i], recv_buf[i])
            return
        }
    }
}

func test_udp_communication(t *testing.t) {
    server_sock, err := new_raw_socket(af_inet, sock_dgram, ipproto_udp)
    if err != nil {
        t.errorf("Failed to create server socket: %v", err)
        return
    }
    defer server_sock.close()
    err = server_sock.udp_bind("127.0.0.1", 19999)
    if err != nil {
        t.errorf("Failed to bind server: %v", err)
        return
    }
    client_sock, err := new_raw_socket(af_inet, sock_dgram, ipproto_udp)
    if err != nil {
        t.errorf("Failed to create client socket: %v", err)
        return
    }
    defer client_sock.close()
    err = client_sock.udp_bind("127.0.0.1", 0)
    if err != nil {
        t.errorf("Failed to bind client: %v", err)
        return
    }
    test_data := byte[]{'h', 'e', 'l', 'l', 'o', 'u', 'd', 'p'}
    n, err := client_sock.send_to(test_data, "127.0.0.1", 19999)
    if err != nil {
        t.errorf("Failed to send UDP data: %v", err)
        return
    }
    if n != len(test_data) {
        t.errorf("Expected to send %d bytes, sent %d bytes", len(test_data), n)
        return
    }
    var recv_buf = [256]byte{}
    n, src_ip, src_port, err := server_sock.recv_from(recv_buf[:])
    if err != nil {
        t.errorf("Failed to receive UDP data: %v", err)
        return
    }
    if n != len(test_data) {
        t.errorf("Expected to receive %d bytes, received %d bytes", len(test_data), n)
        return
    }
    for i := 0; i < n; i++ {
        if recv_buf[i] != test_data[i] {
            t.errorf("Received data mismatch at index %d: expected %d, got %d", i, test_data[i], recv_buf[i])
            return
        }
    }
}

func test_timeout_handling(t *testing.t) {
    sock, err := new_raw_socket(af_inet, sock_stream, ipproto_tcp)
    if err != nil {
        t.errorf("Failed to create socket: %v", err)
        return
    }
    defer sock.close()
    now_ns := time.now_ns()
    past_deadline := now_ns - 1000000
    sock.set_read_deadline(past_deadline)
    var buf = [1]byte{}
    _, err = sock.read(buf[:])
    if err == nil {
        t.error("Expected timeout error, got nil")
        return
    }
    if !is_timeout_error(etimedout) {
        t.error("Timeout handling failed")
    }
}

func test_concurrent_connections(t *testing.t) {
    server_sock, err := new_raw_socket(af_inet, sock_stream, ipproto_tcp)
    if err != nil {
        t.errorf("Failed to create server socket: %v", err)
        return
    }
    defer server_sock.close()
    server_sock.set_reuse_addr(true)
    err = server_sock.bind("127.0.0.1", 19997)
    if err != nil {
        t.errorf("Failed to bind server: %v", err)
        return
    }
    err = server_sock.listen(5)
    if err != nil {
        t.errorf("Failed to listen: %v", err)
        return
    }
    var clients [3]*raw_socket
    var i = 0
    for i < 3 {
        client, err := new_raw_socket(af_inet, sock_stream, ipproto_tcp)
        if err != nil {
            t.errorf("Failed to create client %d: %v", i, err)
            return
        }
        err = client.connect("127.0.0.1", 19997, 1000)
        if err != nil {
            t.errorf("Failed to connect client %d: %v", i, err)
            return
        }
        clients[i] = client
        i = i + 1
    }
    var j = 0
    for j < 3 {
        accept_sock, err := server_sock.accept()
        if err != nil {
            t.errorf("Failed to accept connection %d: %v", j, err)
            return
        }
        defer accept_sock.close()
        j = j + 1
    }
    var k = 0
    for k < 3 {
        clients[k].close()
        k = k + 1
    }
}
