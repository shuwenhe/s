// PacketConn 相关方法（伪实现）
func (c *TCPConn) ReadFrom([]byte buf) (int, Addr, error) {
    // TODO: 仅为接口兼容，TCPConn 通常不实现 ReadFrom
    0, nil, "not implemented"
}

func (c *TCPConn) WriteTo([]byte buf, Addr addr) (int, error) {
    // TODO: 仅为接口兼容，TCPConn 通常不实现 WriteTo
    0, "not implemented"
}

func (c *TCPConn) SetDeadline(int64 t) error {
    // TODO: 设置超时
    nil
}

func (c *TCPConn) SetReadDeadline(int64 t) error {
    // TODO: 设置读超时
    nil
}

func (c *TCPConn) SetWriteDeadline(int64 t) error {
    // TODO: 设置写超时
    nil
}
package src.net

// TCPConn 结构体（伪实现）
struct TCPConn {
    int fd
    TCPAddr laddr
    TCPAddr raddr
}

// 可实现 Conn 接口方法（伪实现，需底层 socket 支持）
func (c *TCPConn) Read([]byte buf) (int, error) {
    // 实际调用 socket read
    n = read(c.fd, buf)
    if n < 0 {
        return 0, "read error"
    }
    return n, nil
}

func (c *TCPConn) Write([]byte buf) (int, error) {
    // 实际调用 socket write
    n = write(c.fd, buf)
    if n < 0 {
        return 0, "write error"
    }
    return n, nil
}

func (c *TCPConn) Close() error {
    // 实际关闭 socket
    if close(c.fd) != 0 {
        return "close error"
    }
    nil
}

func (c *TCPConn) LocalAddr() Addr {
    &c.laddr
}

func (c *TCPConn) RemoteAddr() Addr {
    &c.raddr
}

func (c *TCPConn) SetDeadline(int64 t) error {
    // TODO: 设置超时
    nil
}

func (c *TCPConn) SetReadDeadline(int64 t) error {
    // TODO: 设置读超时
    nil
}

func (c *TCPConn) SetWriteDeadline(int64 t) error {
    // TODO: 设置写超时
    nil
}
