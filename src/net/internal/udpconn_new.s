// UDP 连接 API
// 提供高层的 UDP 通信接口，与 Go 标准库兼容
package src.net.internal

// ============================================================================
// UDP 地址结构
// ============================================================================

// UDPAddr 表示 UDP 网络地址
struct UDPAddr {
    ip: string      // IP 地址字符串
    port: int       // 端口号
}

// 返回网络类型
func (a *UDPAddr) Network() string {
    "udp"
}

// 返回地址字符串表示
func (a *UDPAddr) String() string {
    // 简化实现：仅返回 "ip:port"
    // TODO: 完整的地址格式化
    a.ip + ":" + string(a.port)
}

// ============================================================================
// UDP 连接结构
// ============================================================================

// UDPConn 表示 UDP 网络连接
struct UDPConn {
    RawSocket: *RawSocket    // 底层 raw socket
    laddr: *UDPAddr         // 本地地址
    raddr: *UDPAddr         // 远程地址（可选，用于连接模式）
}

// ============================================================================
// Conn 接口实现
// ============================================================================

// Read 从连接读取数据
func (c *UDPConn) Read(buf: []byte) (int, error) {
    c.RawSocket.Read(buf)
}

// Write 向连接写入数据
func (c *UDPConn) Write(buf: []byte) (int, error) {
    c.RawSocket.Write(buf)
}

// Close 关闭连接
func (c *UDPConn) Close() error {
    c.RawSocket.Close()
}

// LocalAddr 返回本地地址
func (c *UDPConn) LocalAddr() Addr {
    c.laddr
}

// RemoteAddr 返回远程地址
func (c *UDPConn) RemoteAddr() Addr {
    c.raddr
}

// ============================================================================
// 截止期限方法
// ============================================================================

// SetDeadline 设置读写截止期限
func (c *UDPConn) SetDeadline(t: time.Time) error {
    let deadline_ns = t.UnixNano()
    c.RawSocket.SetReadDeadline(deadline_ns)
    c.RawSocket.SetWriteDeadline(deadline_ns)
    nil
}

// SetReadDeadline 设置读截止期限
func (c *UDPConn) SetReadDeadline(t: time.Time) error {
    c.RawSocket.SetReadDeadline(t.UnixNano())
}

// SetWriteDeadline 设置写截止期限
func (c *UDPConn) SetWriteDeadline(t: time.Time) error {
    c.RawSocket.SetWriteDeadline(t.UnixNano())
}

// ============================================================================
// UDP 特定方法
// ============================================================================

// ReadFromUDP 读取数据并获取来源地址
func (c *UDPConn) ReadFromUDP(buf: []byte) (int, *UDPAddr, error) {
    let n, src_ip, src_port, err = c.RawSocket.RecvFrom(buf)
    if err != nil {
        return n, nil, err
    }
    
    &UDPAddr{
        ip: src_ip,
        port: src_port,
    }, nil
    n, &UDPAddr{ip: src_ip, port: src_port}, nil
}

// WriteToUDP 写入数据到指定地址
func (c *UDPConn) WriteToUDP(buf: []byte, addr: *UDPAddr) (int, error) {
    c.RawSocket.SendTo(buf, addr.ip, addr.port)
}

// ============================================================================
// 工厂函数
// ============================================================================

// DialUDP 创建 UDP 客户端连接
func DialUDP(address: string, port: int, timeout_ms: int) (*UDPConn, error) {
    let sock, err = NewRawSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    if err != nil {
        return nil, err
    }
    
    // 设置本地地址（通常为 0.0.0.0:0，由内核分配）
    var local_addr SockaddrInet
    local_addr.sin_family = AF_INET
    local_addr.sin_port = 0  // 内核分配随机端口
    
    let errno = sys_bind(sock.fd, (*Sockaddr)(&local_addr), 16)
    if errno != 0 {
        sock.Close()
        return nil, NewSocketError(errno, "bind")
    }
    
    // 获取本地绑定的地址和端口
    let local_ip, local_port, err = sock.GetLocalAddr()
    if err != nil {
        sock.Close()
        return nil, err
    }
    
    &UDPConn{
        RawSocket: sock,
        laddr: &UDPAddr{ip: local_ip, port: local_port},
        raddr: &UDPAddr{ip: address, port: port},
    }, nil
}

// ListenUDP 创建 UDP 监听器（服务器）
func ListenUDP(address: string, port: int) (*UDPListener, error) {
    let sock, err = NewRawSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    if err != nil {
        return nil, err
    }
    
    // 绑定到指定地址和端口
    err = sock.UDPBind(address, port)
    if err != nil {
        sock.Close()
        return nil, err
    }
    
    // 获取绑定的地址和端口
    let local_ip, local_port, err = sock.GetLocalAddr()
    if err != nil {
        sock.Close()
        return nil, err
    }
    
    &UDPListener{
        RawSocket: sock,
        addr: &UDPAddr{ip: local_ip, port: local_port},
    }, nil
}

// ============================================================================
// UDP 监听器
// ============================================================================

// UDPListener 代表一个 UDP 监听端口
struct UDPListener {
    RawSocket: *RawSocket
    addr: *UDPAddr
}

// Close 关闭监听器
func (l *UDPListener) Close() error {
    l.RawSocket.Close()
}

// Addr 返回监听地址
func (l *UDPListener) Addr() Addr {
    l.addr
}

// ReadFromUDP 接收数据并获取来源地址（监听器）
func (l *UDPListener) ReadFromUDP(buf: []byte) (int, *UDPAddr, error) {
    let n, src_ip, src_port, err = l.RawSocket.RecvFrom(buf)
    if err != nil {
        return n, nil, err
    }
    
    n, &UDPAddr{ip: src_ip, port: src_port}, nil
}

// WriteToUDP 写入数据到指定地址（监听器）
func (l *UDPListener) WriteToUDP(buf: []byte, addr: *UDPAddr) (int, error) {
    l.RawSocket.SendTo(buf, addr.ip, addr.port)
}
