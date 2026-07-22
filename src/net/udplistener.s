func (l *UDPListener) Close() error {
    if close(l.fd) != 0 {
        return "close error"
    }
    nil
}

func (l *UDPListener) Addr() Addr {
    &l.laddr
}
package src.net

struct UDPListener {
    int fd
    UDPAddr laddr
}
