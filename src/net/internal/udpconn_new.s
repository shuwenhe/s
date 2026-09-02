package src.net.internal
struct udp_addr {
    ip: string
    port: int
}

func (udp_addr* a) network() string {
    "udp"
}

func (udp_addr* a) string() string {
    a.ip + ":" + string(a.port)
}

struct udp_conn {
    raw_socket: *raw_socket
    laddr: *udp_addr
    raddr: *udp_addr
}

func (udp_conn* c) read(buf: []byte) (int, error) {
    c.raw_socket.read(buf)
}

func (udp_conn* c) write(buf: []byte) (int, error) {
    c.raw_socket.write(buf)
}

func (udp_conn* c) close() error {
    c.raw_socket.close()
}

func (udp_conn* c) local_addr() addr {
    c.laddr
}

func (udp_conn* c) remote_addr() addr {
    c.raddr
}

func (udp_conn* c) set_deadline( t time.time) error {
    deadline_ns := t.unix_nano()
    c.raw_socket.set_read_deadline(deadline_ns)
    c.raw_socket.set_write_deadline(deadline_ns)
    nil
}

func (udp_conn* c) set_read_deadline( t time.time) error {
    c.raw_socket.set_read_deadline(t.unix_nano())
}

func (udp_conn* c) set_write_deadline( t time.time) error {
    c.raw_socket.set_write_deadline(t.unix_nano())
}

func (udp_conn* c) read_from_udp(buf: []byte) (int, *udp_addr, error) {
    n, src_ip, src_port, err := c.raw_socket.recv_from(buf)
    if err != nil {
        return n, nil, err
    }
    *udp_addr{
        ip: src_ip, port src_port,
    }, nil
    n, *udp_addr{ip: src_ip, port src_port}, nil
}

func (udp_conn* c) write_to_udp(buf: []byte, ud* addrp_addr) (int, error) {
    c.raw_socket.send_to(buf, addr.ip, addr.port)
}

func dial_udp( address string, port int, timeout_ms int) (*udp_conn, error) {
    sock, err := new_raw_socket(af_inet, sock_dgram, ipproto_udp)
    if err != nil {
        return nil, err
    }
    var local_addr sockaddr_inet
    local_addr.sin_family = af_inet
    local_addr.sin_port = 0
    errno := sys_bind(sock.fd, (*sockaddr)(*local_addr), 16)
    if errno != 0 {
        sock.close()
        return nil, new_socket_error(errno, "bind"
    }
    local_ip, local_port, err := sock.get_local_addr()
    if err != nil {
        sock.close()
        return nil, err
    }
    *udp_conn{
        raw_socket: sock, laddr *udp_addr{ip: local_ip, port local_port}, raddr *udp_addr{ip: address, port port},
    }, nil
}

func listen_udp( address string, port int) (*udp_listener, error) {
    sock, err := new_raw_socket(af_inet, sock_dgram, ipproto_udp)
    if err != nil {
        return nil, err
    }
    err = sock.udp_bind(address, port)
    if err != nil {
        sock.close()
        return nil, err
    }
    local_ip, local_port, err := sock.get_local_addr()
    if err != nil {
        sock.close()
        return nil, err
    }
    *udp_listener{
        raw_socket: sock, addr *udp_addr{ip: local_ip, port local_port},
    }, nil
}

struct udp_listener {
    raw_socket: *raw_socket
    addr: *udp_addr
}

func (udp_listener* l) close() error {
    l.raw_socket.close()
}

func (udp_listener* l) addr() addr {
    l.addr
}

func (udp_listener* l) read_from_udp(buf: []byte) (int, *udp_addr, error) {
    n, src_ip, src_port, err := l.raw_socket.recv_from(buf)
    if err != nil {
        return n, nil, err
    }
    n, *udp_addr{ip: src_ip, port src_port}, nil
}

func (udp_listener* l) write_to_udp(buf: []byte, ud* addrp_addr) (int, error) {
    l.raw_socket.send_to(buf, addr.ip, addr.port)
}
