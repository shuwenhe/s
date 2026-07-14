// TCP 连接实现 - 使用系统调用层
package src.net

import "src.net.internal"

// TCPAddr 结构体
struct TCPAddr {
    string ip
    int port
}

func (a *TCPAddr) Network() string {
    "tcp"
}

func (a *TCPAddr) String() string {
    a.ip + ":" + itoa(a.port)
}

// TCPConn 结构体 - TCP 连接
struct TCPConn {
    *internal.RawSocket
    laddr *TCPAddr      // 本地地址
    raddr *TCPAddr      // 远程地址
}

// ============================================================================
// Conn 接口实现
// ============================================================================

// 从 TCP 连接读取数据
func (c *TCPConn) Read(buf []byte) (int, error) {
    if c.RawSocket == nil {
        return 0, "connection closed"
    }
    c.RawSocket.Read(buf)
}

// 向 TCP 连接写入数据
func (c *TCPConn) Write(buf []byte) (int, error) {
    if c.RawSocket == nil {
        return 0, "connection closed"
    }
    c.RawSocket.Write(buf)
}

// 关闭 TCP 连接
func (c *TCPConn) Close() error {
    if c.RawSocket == nil {
        return "already closed"
    }
    c.RawSocket.Close()
}

// 获取本地地址
func (c *TCPConn) LocalAddr() Addr {
    c.laddr
}

// 获取远程地址
func (c *TCPConn) RemoteAddr() Addr {
    c.raddr
}

// ============================================================================
// PacketConn 接口实现（部分）
// ============================================================================

// TCP 通常不实现 ReadFrom
func (c *TCPConn) ReadFrom(buf []byte) (int, Addr, error) {
    // TCP 是字节流协议，不支持 ReadFrom
    0, nil, "tcp does not support ReadFrom"
}

// TCP 通常不实现 WriteTo
func (c *TCPConn) WriteTo(buf []byte, addr Addr) (int, error) {
    // TCP 是字节流协议，不支持 WriteTo
    0, "tcp does not support WriteTo"
}

// ============================================================================
// 超时设置
// ============================================================================

// 设置读写超时截止期限
func (c *TCPConn) SetDeadline(deadline_ns i64) error {
    if c.RawSocket == nil {
        return "connection closed"
    }
    
    err1 := c.SetReadDeadline(deadline_ns)
    err2 := c.SetWriteDeadline(deadline_ns)
    
    if err1 != nil {
        return err1
    }
    err2
}

// 设置读超时
func (c *TCPConn) SetReadDeadline(deadline_ns i64) error {
    if c.RawSocket == nil {
        return "connection closed"
    }
    c.RawSocket.SetReadDeadline(deadline_ns)
}

// 设置写超时
func (c *TCPConn) SetWriteDeadline(deadline_ns i64) error {
    if c.RawSocket == nil {
        return "connection closed"
    }
    c.RawSocket.SetWriteDeadline(deadline_ns)
}

// ============================================================================
// TCP 连接选项
// ============================================================================

// 禁用 Nagle 算法
func (c *TCPConn) SetNoDelay(on bool) error {
    if c.RawSocket == nil {
        return "connection closed"
    }
    c.RawSocket.SetTCPNoDelay(on)
}

// 设置 SO_REUSEADDR
func (c *TCPConn) SetReuseAddr(on bool) error {
    if c.RawSocket == nil {
        return "connection closed"
    }
    c.RawSocket.SetReuseAddr(on)
}

// 设置 SO_REUSEPORT
func (c *TCPConn) SetReusePort(on bool) error {
    if c.RawSocket == nil {
        return "connection closed"
    }
    c.RawSocket.SetReusePort(on)
}

// ============================================================================
// TCP Dialer
// ============================================================================

// 连接到 TCP 服务器
func DialTCP(address string, port int, timeout_ms int) (*TCPConn, error) {
    // 创建 TCP socket
    sock, err := internal.NewRawSocket(
        internal.AF_INET,
        internal.SOCK_STREAM,
        internal.IPPROTO_TCP,
    )
    if err != nil {
        return nil, err
    }
    
    // 连接到远程地址
    err = sock.Connect(address, port, timeout_ms)
    if err != nil {
        sock.Close()
        return nil, err
    }
    
    // 获取本地和远程地址
    local_ip, local_port, _ := sock.GetLocalAddr()
    remote_ip, remote_port, _ := sock.GetRemoteAddr()
    
    &TCPConn{
        RawSocket: sock,
        laddr: &TCPAddr{ip: local_ip, port: local_port},
        raddr: &TCPAddr{ip: remote_ip, port: remote_port},
    }, nil
}

// ============================================================================
// TCP Listener
// ============================================================================

// TCPListener 结构体 - TCP 监听器
struct TCPListener {
    *internal.RawSocket
    addr *TCPAddr
}

// 创建 TCP 监听器
func ListenTCP(address string, port int) (*TCPListener, error) {
    // 创建 TCP socket
    sock, err := internal.NewRawSocket(
        internal.AF_INET,
        internal.SOCK_STREAM,
        internal.IPPROTO_TCP,
    )
    if err != nil {
        return nil, err
    }
    
    // 设置 SO_REUSEADDR 允许地址重用
    sock.SetReuseAddr(true)
    
    // 绑定到本地地址
    err = sock.Bind(address, port)
    if err != nil {
        sock.Close()
        return nil, err
    }
    
    // 开始监听
    err = sock.Listen(128)  // backlog = 128
    if err != nil {
        sock.Close()
        return nil, err
    }
    
    &TCPListener{
        RawSocket: sock,
        addr: &TCPAddr{ip: address, port: port},
    }, nil
}

// 接受客户端连接
func (l *TCPListener) Accept() (*TCPConn, error) {
    if l.RawSocket == nil {
        return nil, "listener closed"
    }
    
    client_sock, err := l.RawSocket.Accept()
    if err != nil {
        return nil, err
    }
    
    // 获取客户端地址
    remote_ip, remote_port, _ := client_sock.GetRemoteAddr()
    local_ip, local_port, _ := client_sock.GetLocalAddr()
    
    &TCPConn{
        RawSocket: client_sock,
        laddr: &TCPAddr{ip: local_ip, port: local_port},
        raddr: &TCPAddr{ip: remote_ip, port: remote_port},
    }, nil
}

// 关闭监听器
func (l *TCPListener) Close() error {
    if l.RawSocket == nil {
        return "already closed"
    }
    l.RawSocket.Close()
}

// 获取监听地址
func (l *TCPListener) Addr() Addr {
    l.addr
}
