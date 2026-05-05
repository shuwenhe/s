package src.net

// TCPListener 结构体（伪实现）
struct TCPListener {
    int fd
    TCPAddr laddr
}

// 可实现 Listener 接口方法（伪实现，需底层 socket 支持）
func (l *TCPListener) Accept() Conn {
    // 实际调用 accept 获取新 fd
    newfd = accept(l.fd)
    if newfd < 0 {
        return nil
    }
    // 构造新 TCPConn
    TCPConn c = TCPConn { fd: newfd, laddr: l.laddr, raddr: TCPAddr{} }
    &c
}

func (l *TCPListener) Close() error {
    // 实际关闭监听 fd
    if close(l.fd) != 0 {
        return "close error"
    }
    nil
}

func (l *TCPListener) Addr() Addr {
    &l.laddr
}
