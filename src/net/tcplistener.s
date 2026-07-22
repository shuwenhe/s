package src.net

struct TCPListener {
    int fd
    TCPAddr laddr
}

func (l *TCPListener) Accept() Conn {
    newfd = accept(l.fd)
    if newfd < 0 {
        return nil
    }
    TCPConn c = TCPConn { fd: newfd, laddr: l.laddr, raddr: TCPAddr{} }
    &c
}

func (l *TCPListener) Close() error {
    if close(l.fd) != 0 {
        return "close error"
    }
    nil
}

func (l *TCPListener) Addr() Addr {
    &l.laddr
}
