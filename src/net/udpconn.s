// PacketConn 相关方法
func (c *UDPConn) ReadFrom([]byte buf) (int, Addr, error) {
    // TODO: 伪实现，返回本地地址
    n = read(c.fd, buf)
    if n < 0 {
        return 0, nil, "read error"
    }
    return n, &c.laddr, nil
}

func (c *UDPConn) WriteTo([]byte buf, Addr addr) (int, error) {
    // TODO: 伪实现，忽略 addr
    n = write(c.fd, buf)
    if n < 0 {
        return 0, "write error"
    }
    return n, nil
}

func (c *UDPConn) SetDeadline(int64 t) error {
    // TODO: 设置超时
    nil
}

func (c *UDPConn) SetReadDeadline(int64 t) error {
    // TODO: 设置读超时
    nil
}

func (c *UDPConn) SetWriteDeadline(int64 t) error {
    // TODO: 设置写超时
    nil
}
package src.net

// UDPAddr 结构体
struct UDPAddr {
    string ip
    int port
}

func (a *UDPAddr) Network() string {
    "udp"
}

func (a *UDPAddr) String() string {
    a.ip + ":" + itoa(a.port)
}

// UDPConn 结构体（伪实现）
struct UDPConn {
    int fd
    UDPAddr laddr
    UDPAddr raddr
}

// 可实现 Conn 接口方法（伪实现，需底层 socket 支持）
func (c *UDPConn) Read([]byte buf) (int, error) {
    // 实际调用 socket read
    n = read(c.fd, buf)
    if n < 0 {
        return 0, "read error"
    }
    return n, nil
}

func (c *UDPConn) Write([]byte buf) (int, error) {
    // 实际调用 socket write
    n = write(c.fd, buf)
    if n < 0 {
        return 0, "write error"
    }
    return n, nil
}

func (c *UDPConn) Close() error {
    // 实际关闭 socket
    if close(c.fd) != 0 {
        return "close error"
    }
    nil
}

func (c *UDPConn) LocalAddr() Addr {
    &c.laddr
}

func (c *UDPConn) RemoteAddr() Addr {
    &c.raddr
}

func (c *UDPConn) SetDeadline(int64 t) error {
    // TODO: 设置超时
    nil
}

func (c *UDPConn) SetReadDeadline(int64 t) error {
    // TODO: 设置读超时
    nil
}

func (c *UDPConn) SetWriteDeadline(int64 t) error {
    // TODO: 设置写超时
    nil
}
