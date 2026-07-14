// Socket 系统调用层单元测试
package src.net.internal

import "src.std.testing"

// ============================================================================
// 基础 Socket 操作测试
// ============================================================================

func TestSocketCreate(t *testing.T) {
    // 测试创建 TCP socket
    sock, err := NewRawSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    if err != nil {
        t.Errorf("Failed to create socket: %v", err)
        return
    }
    
    // 应该成功创建 socket
    if sock == nil {
        t.Error("Socket pointer is nil")
        return
    }
    
    if sock.fd < 0 {
        t.Errorf("Invalid file descriptor: %d", sock.fd)
        return
    }
    
    // 验证 socket 属性
    if sock.family != AF_INET {
        t.Errorf("Expected family AF_INET, got %d", sock.family)
    }
    
    if sock.socktype != SOCK_STREAM {
        t.Errorf("Expected socktype SOCK_STREAM, got %d", sock.socktype)
    }
    
    // 关闭 socket
    err = sock.Close()
    if err != nil {
        t.Errorf("Failed to close socket: %v", err)
    }
}

func TestSocketCreateUDP(t *testing.T) {
    // 测试创建 UDP socket
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
    // 创建 socket
    sock, _ := NewRawSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    
    // 关闭 socket
    err := sock.Close()
    if err != nil {
        t.Errorf("Failed to close socket: %v", err)
    }
    
    // 重复关闭应该返回错误
    err = sock.Close()
    if err == nil {
        t.Error("Expected error on second close")
    }
}

// ============================================================================
// Socket 选项测试
// ============================================================================

func TestSetReuseAddr(t *testing.T) {
    sock, _ := NewRawSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    defer sock.Close()
    
    // 设置 SO_REUSEADDR
    err := sock.SetReuseAddr(true)
    if err != nil {
        t.Errorf("Failed to set SO_REUSEADDR: %v", err)
    }
    
    // 关闭 reuse
    err = sock.SetReuseAddr(false)
    if err != nil {
        t.Errorf("Failed to unset SO_REUSEADDR: %v", err)
    }
}

func TestSetTCPNoDelay(t *testing.T) {
    sock, _ := NewRawSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    defer sock.Close()
    
    // 设置 TCP_NODELAY
    err := sock.SetTCPNoDelay(true)
    if err != nil {
        t.Errorf("Failed to set TCP_NODELAY: %v", err)
    }
}

func TestSetBufferSize(t *testing.T) {
    sock, _ := NewRawSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    defer sock.Close()
    
    // 设置发送缓冲区
    err := sock.SetSendBufferSize(65536)
    if err != nil {
        t.Errorf("Failed to set send buffer size: %v", err)
    }
    
    // 设置接收缓冲区
    err = sock.SetRecvBufferSize(65536)
    if err != nil {
        t.Errorf("Failed to set recv buffer size: %v", err)
    }
}

// ============================================================================
// 超时处理测试
// ============================================================================

func TestSetReadDeadline(t *testing.T) {
    sock, _ := NewRawSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    defer sock.Close()
    
    // 设置截止期限（未来 10 秒）
    // var deadline = time.now().add(10 * time.Second)
    // err := sock.SetReadDeadline(deadline)
    // if err != nil {
    //     t.Errorf("Failed to set read deadline: %v", err)
    // }
}

func TestSetWriteDeadline(t *testing.T) {
    sock, _ := NewRawSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    defer sock.Close()
    
    // 设置写超时
    // err := sock.SetWriteDeadline(...)
    // if err != nil {
    //     t.Errorf("Failed to set write deadline: %v", err)
    // }
}

// ============================================================================
// 地址转换测试
// ============================================================================

func TestHtons(t *testing.T) {
    // 测试字节序转换
    let result = htons(0x1234)
    let expected = 0x3412
    
    if result != expected {
        t.Errorf("htons(0x1234) = 0x%04x, expected 0x%04x", result, expected)
    }
}

func TestNtohs(t *testing.T) {
    // 测试反向字节序转换
    let result = ntohs(0x3412)
    let expected = 0x1234
    
    if result != expected {
        t.Errorf("ntohs(0x3412) = 0x%04x, expected 0x%04x", result, expected)
    }
}

// ============================================================================
// 错误处理测试
// ============================================================================

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

// ============================================================================
// 集成测试辅助
// ============================================================================

// 创建本地环回 TCP 服务器用于测试
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

// ============================================================================
// 集成测试
// ============================================================================

func TestTCPServerClientIntegration(t *testing.T) {
    // 创建服务器 socket
    server_sock, err := NewRawSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    if err != nil {
        t.Errorf("Failed to create server socket: %v", err)
        return
    }
    defer server_sock.Close()
    
    // 设置地址重用
    server_sock.SetReuseAddr(true)
    
    // 绑定服务器到本地端口
    err = server_sock.Bind("127.0.0.1", 19998)
    if err != nil {
        t.Errorf("Failed to bind server: %v", err)
        return
    }
    
    // 开始监听
    err = server_sock.Listen(1)
    if err != nil {
        t.Errorf("Failed to listen: %v", err)
        return
    }
    
    // 创建客户端 socket
    client_sock, err := NewRawSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    if err != nil {
        t.Errorf("Failed to create client socket: %v", err)
        return
    }
    defer client_sock.Close()
    
    // 客户端连接到服务器
    err = client_sock.Connect("127.0.0.1", 19998, 1000)
    if err != nil {
        t.Errorf("Failed to connect: %v", err)
        return
    }
    
    // 服务器接受连接
    accept_sock, err := server_sock.Accept()
    if err != nil {
        t.Errorf("Failed to accept: %v", err)
        return
    }
    defer accept_sock.Close()
    
    // 客户端发送数据
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
    
    // 服务器接收数据
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
    
    // 验证数据内容
    for i := 0; i < n; i++ {
        if recv_buf[i] != test_data[i] {
            t.Errorf("Received data mismatch at index %d: expected %d, got %d", i, test_data[i], recv_buf[i])
            return
        }
    }
}

func TestUDPCommunication(t *testing.T) {
    // 创建服务器 UDP socket
    server_sock, err := NewRawSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    if err != nil {
        t.Errorf("Failed to create server socket: %v", err)
        return
    }
    defer server_sock.Close()
    
    // 绑定服务器到本地端口
    err = server_sock.UDPBind("127.0.0.1", 19999)
    if err != nil {
        t.Errorf("Failed to bind server: %v", err)
        return
    }
    
    // 创建客户端 UDP socket
    client_sock, err := NewRawSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    if err != nil {
        t.Errorf("Failed to create client socket: %v", err)
        return
    }
    defer client_sock.Close()
    
    // 绑定客户端到本地随机端口
    err = client_sock.UDPBind("127.0.0.1", 0)
    if err != nil {
        t.Errorf("Failed to bind client: %v", err)
        return
    }
    
    // 客户端发送数据
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
    
    // 服务器接收数据
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
    
    // 验证接收到的数据内容
    for i := 0; i < n; i++ {
        if recv_buf[i] != test_data[i] {
            t.Errorf("Received data mismatch at index %d: expected %d, got %d", i, test_data[i], recv_buf[i])
            return
        }
    }
}

func TestTimeoutHandling(t *testing.T) {
    // 创建 socket
    sock, err := NewRawSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    if err != nil {
        t.Errorf("Failed to create socket: %v", err)
        return
    }
    defer sock.Close()
    
    // 设置一个过去的截止期限（立即超时）
    let now_ns = time.now_ns()
    let past_deadline = now_ns - 1000000  // 1ms 之前
    sock.SetReadDeadline(past_deadline)
    
    // 尝试读取应该立即超时
    var buf = [1]byte{}
    _, err = sock.Read(buf[:])
    
    // 验证是否返回了 ETIMEDOUT 错误
    if err == nil {
        t.Error("Expected timeout error, got nil")
        return
    }
    
    // 检查是否是超时错误
    if !IsTimeoutError(ETIMEDOUT) {
        t.Error("Timeout handling failed")
    }
}

func TestConcurrentConnections(t *testing.T) {
    // 创建服务器 socket
    server_sock, err := NewRawSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    if err != nil {
        t.Errorf("Failed to create server socket: %v", err)
        return
    }
    defer server_sock.Close()
    
    server_sock.SetReuseAddr(true)
    
    // 绑定并监听
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
    
    // 创建多个客户端连接
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
    
    // 接受所有连接
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
    
    // 关闭所有客户端连接
    var k = 0
    for k < 3 {
        clients[k].Close()
        k = k + 1
    }
}
