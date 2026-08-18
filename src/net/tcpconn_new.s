package src.net
import "src.net.internal"

struct TCPAddr {
    string ip
    int port
}
func (TCPAddr* a) Network() string {
    "tcp"
}
func (TCPAddr* a) String() string {
    a.ip + ":" + itoa(a.port)
}

struct TCPConn {
    *internal.raw_socket
    laddr *TCPAddr
    raddr *TCPAddr
}
func (TCPConn* c) Read(buf []byte) (int, error) {
    if c.raw_socket == nil {
        return 0, "connection closed"
    }
    c.raw_socket.read(buf)
}
func (TCPConn* c) Write(buf []byte) (int, error) {
    if c.raw_socket == nil {
        return 0, "connection closed"
    }
    c.raw_socket.write(buf)
}
func (TCPConn* c) Close() error {
    if c.raw_socket == nil {
        return "already closed"
    }
    c.raw_socket.close()
}
func (TCPConn* c) LocalAddr() Addr {
    c.laddr
}
func (TCPConn* c) RemoteAddr() Addr {
    c.raddr
}
func (TCPConn* c) ReadFrom(buf []byte) (int, Addr, error) {
    0, nil, "tcp does not support ReadFrom"
}
func (TCPConn* c) WriteTo(buf []byte, addr Addr) (int, error) {
    0, "tcp does not support WriteTo"
}
func (TCPConn* c) SetDeadline(deadline_ns i64) error {
    if c.raw_socket == nil {
        return "connection closed"
    }
    err1 := c.SetReadDeadline(deadline_ns)
    err2 := c.SetWriteDeadline(deadline_ns)
    if err1 != nil {
        return err1
    }
    err2
}
func (TCPConn* c) SetReadDeadline(deadline_ns i64) error {
    if c.raw_socket == nil {
        return "connection closed"
    }
    c.raw_socket.set_read_deadline(deadline_ns)
}
func (TCPConn* c) SetWriteDeadline(deadline_ns i64) error {
    if c.raw_socket == nil {
        return "connection closed"
    }
    c.raw_socket.set_write_deadline(deadline_ns)
}
func (TCPConn* c) SetNoDelay(on bool) error {
    if c.raw_socket == nil {
        return "connection closed"
    }
    c.raw_socket.set_tcp_no_delay(on)
}
func (TCPConn* c) SetReuseAddr(on bool) error {
    if c.raw_socket == nil {
        return "connection closed"
    }
    c.raw_socket.set_reuse_addr(on)
}
func (TCPConn* c) SetReusePort(on bool) error {
    if c.raw_socket == nil {
        return "connection closed"
    }
    c.raw_socket.set_reuse_port(on)
}

func DialTCP(address string, port int, timeout_ms int) (*TCPConn, error) {
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
    &TCPConn{
        raw_socket: sock,
        laddr: &TCPAddr{ip: local_ip, port: local_port},
        raddr: &TCPAddr{ip: remote_ip, port: remote_port},
    }, nil
}

struct TCPListener {
    *internal.raw_socket
    addr *TCPAddr
}

func ListenTCP(address string, port int) (*TCPListener, error) {
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
    &TCPListener{
        raw_socket: sock,
        addr: &TCPAddr{ip: address, port: port},
    }, nil
}
func (TCPListener* l) Accept() (*TCPConn, error) {
    if l.raw_socket == nil {
        return nil, "listener closed"
    }
    client_sock, err := l.raw_socket.accept()
    if err != nil {
        return nil, err
    }
    remote_ip, remote_port, _ := client_sock.get_remote_addr()
    local_ip, local_port, _ := client_sock.get_local_addr()
    &TCPConn{
        raw_socket: client_sock,
        laddr: &TCPAddr{ip: local_ip, port: local_port},
        raddr: &TCPAddr{ip: remote_ip, port: remote_port},
    }, nil
}
func (TCPListener* l) Close() error {
    if l.raw_socket == nil {
        return "already closed"
    }
    l.raw_socket.close()
}
func (TCPListener* l) Addr() Addr {
    l.addr
}
