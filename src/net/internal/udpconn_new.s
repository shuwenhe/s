package src.net.internal

struct UDPAddr {
    ip: string
    port: int
}
func (UDPAddr* a) Network() string {
    "udp"
}
func (UDPAddr* a) String() string {
    a.ip + ":" + string(a.port)
}

struct UDPConn {
    raw_socket: *raw_socket
    laddr: *UDPAddr
    raddr: *UDPAddr
}
func (UDPConn* c) Read(buf: []byte) (int, error) {
    c.raw_socket.read(buf)
}
func (UDPConn* c) Write(buf: []byte) (int, error) {
    c.raw_socket.write(buf)
}
func (UDPConn* c) Close() error {
    c.raw_socket.close()
}
func (UDPConn* c) LocalAddr() Addr {
    c.laddr
}
func (UDPConn* c) RemoteAddr() Addr {
    c.raddr
}
func (UDPConn* c) SetDeadline(t: time.Time) error {
    let deadline_ns = t.UnixNano()
    c.raw_socket.set_read_deadline(deadline_ns)
    c.raw_socket.set_write_deadline(deadline_ns)
    nil
}
func (UDPConn* c) SetReadDeadline(t: time.Time) error {
    c.raw_socket.set_read_deadline(t.UnixNano())
}
func (UDPConn* c) SetWriteDeadline(t: time.Time) error {
    c.raw_socket.set_write_deadline(t.UnixNano())
}
func (UDPConn* c) ReadFromUDP(buf: []byte) (int, *UDPAddr, error) {
    let n, src_ip, src_port, err = c.raw_socket.recv_from(buf)
    if err != nil {
        return n, nil, err
    }
    &UDPAddr{
        ip: src_ip,
        port: src_port,
    }, nil
    n, &UDPAddr{ip: src_ip, port: src_port}, nil
}
func (UDPConn* c) WriteToUDP(buf: []byte, addr: *UDPAddr) (int, error) {
    c.raw_socket.send_to(buf, addr.ip, addr.port)
}

func DialUDP(address: string, port: int, timeout_ms: int) (*UDPConn, error) {
    let sock, err = new_raw_socket(af_inet, sock_dgram, ipproto_udp)
    if err != nil {
        return nil, err
    }
    var local_addr sockaddr_inet
    local_addr.sin_family = af_inet
    local_addr.sin_port = 0
    let errno = sys_bind(sock.fd, (*sockaddr)(&local_addr), 16)
    if errno != 0 {
        sock.close()
        return nil, new_socket_error(errno, "bind")
    }
    let local_ip, local_port, err = sock.get_local_addr()
    if err != nil {
        sock.close()
        return nil, err
    }
    &UDPConn{
        raw_socket: sock,
        laddr: &UDPAddr{ip: local_ip, port: local_port},
        raddr: &UDPAddr{ip: address, port: port},
    }, nil
}

func ListenUDP(address: string, port: int) (*UDPListener, error) {
    let sock, err = new_raw_socket(af_inet, sock_dgram, ipproto_udp)
    if err != nil {
        return nil, err
    }
    err = sock.udp_bind(address, port)
    if err != nil {
        sock.close()
        return nil, err
    }
    let local_ip, local_port, err = sock.get_local_addr()
    if err != nil {
        sock.close()
        return nil, err
    }
    &UDPListener{
        raw_socket: sock,
        addr: &UDPAddr{ip: local_ip, port: local_port},
    }, nil
}

struct UDPListener {
    raw_socket: *raw_socket
    addr: *UDPAddr
}
func (UDPListener* l) Close() error {
    l.raw_socket.close()
}
func (UDPListener* l) Addr() Addr {
    l.addr
}
func (UDPListener* l) ReadFromUDP(buf: []byte) (int, *UDPAddr, error) {
    let n, src_ip, src_port, err = l.raw_socket.recv_from(buf)
    if err != nil {
        return n, nil, err
    }
    n, &UDPAddr{ip: src_ip, port: src_port}, nil
}
func (UDPListener* l) WriteToUDP(buf: []byte, addr: *UDPAddr) (int, error) {
    l.raw_socket.send_to(buf, addr.ip, addr.port)
}
