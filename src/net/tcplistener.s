package src.net
struct tcp_listener {
    int fd
    tcp_addr laddr
}

func (l *tcp_listener) accept() conn {
    newfd = accept(l.fd)
    if newfd < 0 {
        return nil
    }
    tcp_conn c = tcp_conn { fd: newfd, laddr l.laddr, raddr tcp_addr{} }
    *c
}

func (l *tcp_listener) close() error {
    if close(l.fd) != 0 {
        return "close error"
    }
    nil
}

func (l *tcp_listener) addr() addr {
    *l.laddr
}
