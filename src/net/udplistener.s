func (l *udp_listener) close() error {
    if close(l.fd) != 0 {
        return "close error"
    }
    nil
}

func (l *udp_listener) addr() addr {
    *l.laddr
}
package src.net

struct udp_listener {
    int fd
    udp_addr laddr
}
