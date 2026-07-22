package src.net.internal

import "src.std.testing"

func TestSocketCreate(t *testing.T) {
    sock, err := NewRawSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    if err != nil {
        t.Errorf("Failed to create socket: %v", err)
        return
    }

    if sock == nil {
        t.Error("Socket pointer is nil")
        return
    }

    if sock.fd < 0 {
        t.Errorf("Invalid file descriptor: %d", sock.fd)
        return
    }

    if sock.family != AF_INET {
        t.Errorf("Expected family AF_INET, got %d", sock.family)
    }

    if sock.socktype != SOCK_STREAM {
        t.Errorf("Expected socktype SOCK_STREAM, got %d", sock.socktype)
    }

    err = sock.Close()
    if err != nil {
        t.Errorf("Failed to close socket: %v", err)
    }
}

func TestSocketCreateUDP(t *testing.T) {
    sock, err := NewRawSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    if err != nil {
        t.Errorf("Failed to create UDP socket: %v", err)
        return
    }

    if sock == nil {
        t.Error("UDP socket pointer is nil")
        return
    }

    if sock.socktype != SOCK_DGRAM {
        t.Errorf("Expected SOCK_DGRAM, got %d", sock.socktype)
    }

    sock.Close()
}

func TestSocketClose(t *testing.T) {
    sock, _ := NewRawSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)

    err := sock.Close()
    if err != nil {
        t.Errorf("Failed to close socket: %v", err)
    }

    err = sock.Close()
    if err == nil {
        t.Error("Expected error on second close")
    }
}

func TestSetReuseAddr(t *testing.T) {
    sock, _ := NewRawSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    defer sock.Close()

    err := sock.SetReuseAddr(true)
    if err != nil {
        t.Errorf("Failed to set SO_REUSEADDR: %v", err)
    }

    err = sock.SetReuseAddr(false)
    if err != nil {
        t.Errorf("Failed to unset SO_REUSEADDR: %v", err)
    }
}

func TestSetTCPNoDelay(t *testing.T) {
    sock, _ := NewRawSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    defer sock.Close()

    err := sock.SetTCPNoDelay(true)
    if err != nil {
        t.Errorf("Failed to set TCP_NODELAY: %v", err)
    }
}

func TestSetBufferSize(t *testing.T) {
    sock, _ := NewRawSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    defer sock.Close()

    err := sock.SetSendBufferSize(65536)
    if err != nil {
        t.Errorf("Failed to set send buffer size: %v", err)
    }

    err = sock.SetRecvBufferSize(65536)
    if err != nil {
        t.Errorf("Failed to set recv buffer size: %v", err)
    }
}

func TestSetReadDeadline(t *testing.T) {
    sock, _ := NewRawSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    defer sock.Close()

}

func TestSetWriteDeadline(t *testing.T) {
    sock, _ := NewRawSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    defer sock.Close()

}

func TestHtons(t *testing.T) {
    let result = htons(0x1234)
    let expected = 0x3412

    if result != expected {
        t.Errorf("htons(0x1234) = 0x%04x, expected 0x%04x", result, expected)
    }
}

func TestNtohs(t *testing.T) {
    let result = ntohs(0x3412)
    let expected = 0x1234

    if result != expected {
        t.Errorf("ntohs(0x3412) = 0x%04x, expected 0x%04x", result, expected)
    }
}

func TestSocketError(t *testing.T) {
    let err = NewSocketError(ECONNREFUSED, "connect")
    if err == nil {
        t.Error("Failed to create socket error")
        return
    }

    if err.errno != ECONNREFUSED {
        t.Errorf("Expected errno %d, got %d", ECONNREFUSED, err.errno)
    }

    if err.syscall_name != "connect" {
        t.Errorf("Expected syscall name 'connect', got '%s'", err.syscall_name)
    }
}

func TestIsTemporaryError(t *testing.T) {
    if !IsTemporaryError(EAGAIN) {
        t.Error("EAGAIN should be temporary error")
    }

    if !IsTemporaryError(EWOULDBLOCK) {
        t.Error("EWOULDBLOCK should be temporary error")
    }

    if IsTemporaryError(ECONNREFUSED) {
        t.Error("ECONNREFUSED should not be temporary error")
    }
}

func TestIsTimeoutError(t *testing.T) {
    if !IsTimeoutError(ETIMEDOUT) {
        t.Error("ETIMEDOUT should be timeout error")
    }

    if IsTimeoutError(EAGAIN) {
        t.Error("EAGAIN should not be timeout error")
    }
}

struct TestServer {
    listener *TCPListener
    port int
}

func (ts *TestServer) Start(port int) error {
    listener, err := ListenTCP("127.0.0.1", port)
    if err != nil {
        return err
    }

    ts.listener = listener
    ts.port = port
    nil
}

func (ts *TestServer) Stop() error {
    if ts.listener != nil {
        ts.listener.Close()
    }
    nil
}

func TestTCPServerClientIntegration(t *testing.T) {
    server_sock, err := NewRawSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    if err != nil {
        t.Errorf("Failed to create server socket: %v", err)
        return
    }
    defer server_sock.Close()

    server_sock.SetReuseAddr(true)

    err = server_sock.Bind("127.0.0.1", 19998)
    if err != nil {
        t.Errorf("Failed to bind server: %v", err)
        return
    }

    err = server_sock.Listen(1)
    if err != nil {
        t.Errorf("Failed to listen: %v", err)
        return
    }

    client_sock, err := NewRawSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    if err != nil {
        t.Errorf("Failed to create client socket: %v", err)
        return
    }
    defer client_sock.Close()

    err = client_sock.Connect("127.0.0.1", 19998, 1000)
    if err != nil {
        t.Errorf("Failed to connect: %v", err)
        return
    }

    accept_sock, err := server_sock.Accept()
    if err != nil {
        t.Errorf("Failed to accept: %v", err)
        return
    }
    defer accept_sock.Close()

    test_data := []byte{'H', 'i', 'T', 'C', 'P'}
    n, err := client_sock.Write(test_data)
    if err != nil {
        t.Errorf("Failed to write: %v", err)
        return
    }

    if n != len(test_data) {
        t.Errorf("Expected to write %d bytes, wrote %d bytes", len(test_data), n)
        return
    }

    var recv_buf = [256]byte{}
    n, err = accept_sock.Read(recv_buf[:])
    if err != nil {
        t.Errorf("Failed to read: %v", err)
        return
    }

    if n != len(test_data) {
        t.Errorf("Expected to read %d bytes, read %d bytes", len(test_data), n)
        return
    }

    for i := 0; i < n; i++ {
        if recv_buf[i] != test_data[i] {
            t.Errorf("Received data mismatch at index %d: expected %d, got %d", i, test_data[i], recv_buf[i])
            return
        }
    }
}

func TestUDPCommunication(t *testing.T) {
    server_sock, err := NewRawSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    if err != nil {
        t.Errorf("Failed to create server socket: %v", err)
        return
    }
    defer server_sock.Close()

    err = server_sock.UDPBind("127.0.0.1", 19999)
    if err != nil {
        t.Errorf("Failed to bind server: %v", err)
        return
    }

    client_sock, err := NewRawSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    if err != nil {
        t.Errorf("Failed to create client socket: %v", err)
        return
    }
    defer client_sock.Close()

    err = client_sock.UDPBind("127.0.0.1", 0)
    if err != nil {
        t.Errorf("Failed to bind client: %v", err)
        return
    }

    test_data := []byte{'H', 'e', 'l', 'l', 'o', 'U', 'D', 'P'}
    n, err := client_sock.SendTo(test_data, "127.0.0.1", 19999)
    if err != nil {
        t.Errorf("Failed to send UDP data: %v", err)
        return
    }

    if n != len(test_data) {
        t.Errorf("Expected to send %d bytes, sent %d bytes", len(test_data), n)
        return
    }

    var recv_buf = [256]byte{}
    n, src_ip, src_port, err := server_sock.RecvFrom(recv_buf[:])
    if err != nil {
        t.Errorf("Failed to receive UDP data: %v", err)
        return
    }

    if n != len(test_data) {
        t.Errorf("Expected to receive %d bytes, received %d bytes", len(test_data), n)
        return
    }

    for i := 0; i < n; i++ {
        if recv_buf[i] != test_data[i] {
            t.Errorf("Received data mismatch at index %d: expected %d, got %d", i, test_data[i], recv_buf[i])
            return
        }
    }
}

func TestTimeoutHandling(t *testing.T) {
    sock, err := NewRawSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    if err != nil {
        t.Errorf("Failed to create socket: %v", err)
        return
    }
    defer sock.Close()

    let now_ns = time.now_ns()
    let past_deadline = now_ns - 1000000
    sock.SetReadDeadline(past_deadline)

    var buf = [1]byte{}
    _, err = sock.Read(buf[:])

    if err == nil {
        t.Error("Expected timeout error, got nil")
        return
    }

    if !IsTimeoutError(ETIMEDOUT) {
        t.Error("Timeout handling failed")
    }
}

func TestConcurrentConnections(t *testing.T) {
    server_sock, err := NewRawSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    if err != nil {
        t.Errorf("Failed to create server socket: %v", err)
        return
    }
    defer server_sock.Close()

    server_sock.SetReuseAddr(true)

    err = server_sock.Bind("127.0.0.1", 19997)
    if err != nil {
        t.Errorf("Failed to bind server: %v", err)
        return
    }

    err = server_sock.Listen(5)
    if err != nil {
        t.Errorf("Failed to listen: %v", err)
        return
    }

    var clients [3]*RawSocket
    var i = 0
    for i < 3 {
        client, err := NewRawSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        if err != nil {
            t.Errorf("Failed to create client %d: %v", i, err)
            return
        }

        err = client.Connect("127.0.0.1", 19997, 1000)
        if err != nil {
            t.Errorf("Failed to connect client %d: %v", i, err)
            return
        }

        clients[i] = client
        i = i + 1
    }

    var j = 0
    for j < 3 {
        accept_sock, err := server_sock.Accept()
        if err != nil {
            t.Errorf("Failed to accept connection %d: %v", j, err)
            return
        }
        defer accept_sock.Close()
        j = j + 1
    }

    var k = 0
    for k < 3 {
        clients[k].Close()
        k = k + 1
    }
}
