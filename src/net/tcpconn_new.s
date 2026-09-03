package src.net
import "src.net.internal"
struct tcp_addr {
    string ip
    int port
}

func (tcp_addr* a) network() string {
    "tcp"
}

func (tcp_addr* a) string() string {
    a.ip + ":" + itoa(a.port)
}

struct tcp_conn {
    *internal.raw_socket
    laddr *tcp_addr
    raddr *tcp_addr
}

func (tcp_conn* c) read(buf byte[]) (int, error) {
    if c.raw_socket == nil {
        return 0, "connection closed"
    }
    c.raw_socket.read(buf)
}

func (tcp_conn* c) write(buf byte[]) (int, error) {
    if c.raw_socket == nil {
        return 0, "connection closed"
    }
    c.raw_socket.write(buf)
}

func (tcp_conn* c) close() error {
    if c.raw_socket == nil {
        return "already closed"
    }
    c.raw_socket.close()
}

func (tcp_conn* c) local_addr() addr {
    c.laddr
}

func (tcp_conn* c) remote_addr() addr {
    c.raddr
}

func (tcp_conn* c) read_from(buf byte[]) (int, addr, error) {
    0, nil, "tcp does not support ReadFrom"
}

func (tcp_conn* c) write_to(buf byte[], addr addr) (int, error) {
    0, "tcp does not support WriteTo"
}

func (tcp_conn* c) set_deadline(deadline_ns i64) error {
    if c.raw_socket == nil {
        return "connection closed"
    }
    err1 := c.set_read_deadline(deadline_ns)
    err2 := c.set_write_deadline(deadline_ns)
    if err1 != nil {
        return err1
    }
    err2
}

func (tcp_conn* c) set_read_deadline(deadline_ns i64) error {
    if c.raw_socket == nil {
        return "connection closed"
    }
    c.raw_socket.set_read_deadline(deadline_ns)
}

func (tcp_conn* c) set_write_deadline(deadline_ns i64) error {
    if c.raw_socket == nil {
        return "connection closed"
    }
    c.raw_socket.set_write_deadline(deadline_ns)
}

func (tcp_conn* c) set_no_delay(on bool) error {
    if c.raw_socket == nil {
        return "connection closed"
    }
    c.raw_socket.set_tcp_no_delay(on)
}

func (tcp_conn* c) set_reuse_addr(on bool) error {
    if c.raw_socket == nil {
        return "connection closed"
    }
    c.raw_socket.set_reuse_addr(on)
}

func (tcp_conn* c) set_reuse_port(on bool) error {
    if c.raw_socket == nil {
        return "connection closed"
    }
    c.raw_socket.set_reuse_port(on)
}

func dial_tcp(address string, port int, timeout_ms int) (*tcp_conn, error) {
    sock, err := internal.new_raw_socket(
        internal.af_inet,
        internal.sock_stream,
        internal.ipproto_tcp,
    )
    if err != nil {
        return nil, err
    }
    err = sock.connect(address, port, timeout_ms)
    if err != nil {
        sock.close()
        return nil, err
    }
    local_ip, local_port, _ := sock.get_local_addr()
    remote_ip, remote_port, _ := sock.get_remote_addr()
    *tcp_conn{
        raw_socket: sock, laddr *tcp_addr{ip: local_ip, port local_port}, raddr *tcp_addr{ip: remote_ip, port remote_port},
    }, nil
}

struct tcp_listener {
    *internal.raw_socket
    addr *tcp_addr
}

func listen_tcp(address string, port int) (*tcp_listener, error) {
    sock, err := internal.new_raw_socket(
        internal.af_inet,
        internal.sock_stream,
        internal.ipproto_tcp,
    )
    if err != nil {
        return nil, err
    }
    sock.set_reuse_addr(true)
    err = sock.bind(address, port)
    if err != nil {
        sock.close()
        return nil, err
    }
    err = sock.listen(128)
    if err != nil {
        sock.close()
        return nil, err
    }
    *tcp_listener{
        raw_socket: sock, addr *tcp_addr{ip: address, port port},
    }, nil
}

func (tcp_listener* l) accept() (*tcp_conn, error) {
    if l.raw_socket == nil {
        return nil, "listener closed"
    }
    client_sock, err := l.raw_socket.accept()
    if err != nil {
        return nil, err
    }
    remote_ip, remote_port, _ := client_sock.get_remote_addr()
    local_ip, local_port, _ := client_sock.get_local_addr()
    *tcp_conn{
        raw_socket: client_sock, laddr *tcp_addr{ip: local_ip, port local_port}, raddr *tcp_addr{ip: remote_ip, port remote_port},
    }, nil
}

func (tcp_listener* l) close() error {
    if l.raw_socket == nil {
        return "already closed"
    }
    l.raw_socket.close()
}

func (tcp_listener* l) addr() addr {
    l.addr
}
