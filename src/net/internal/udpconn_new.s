package src.net.internal

struct UDPAddr {
    ip: string
    port: int
}

func (a *UDPAddr) Network() string {
    "udp"
}

func (a *UDPAddr) String() string {
    a.ip + ":" + string(a.port)
}

struct UDPConn {
    RawSocket: *RawSocket
    laddr: *UDPAddr
    raddr: *UDPAddr
}

func (c *UDPConn) Read(buf: []byte) (int, error) {
    c.RawSocket.Read(buf)
}

func (c *UDPConn) Write(buf: []byte) (int, error) {
    c.RawSocket.Write(buf)
}

func (c *UDPConn) Close() error {
    c.RawSocket.Close()
}

func (c *UDPConn) LocalAddr() Addr {
    c.laddr
}

func (c *UDPConn) RemoteAddr() Addr {
    c.raddr
}

func (c *UDPConn) SetDeadline(t: time.Time) error {
    let deadline_ns = t.UnixNano()
    c.RawSocket.SetReadDeadline(deadline_ns)
    c.RawSocket.SetWriteDeadline(deadline_ns)
    nil
}

func (c *UDPConn) SetReadDeadline(t: time.Time) error {
    c.RawSocket.SetReadDeadline(t.UnixNano())
}

func (c *UDPConn) SetWriteDeadline(t: time.Time) error {
    c.RawSocket.SetWriteDeadline(t.UnixNano())
}

func (c *UDPConn) ReadFromUDP(buf: []byte) (int, *UDPAddr, error) {
    let n, src_ip, src_port, err = c.RawSocket.RecvFrom(buf)
    if err != nil {
        return n, nil, err
    }

    &UDPAddr{
        ip: src_ip,
        port: src_port,
    }, nil
    n, &UDPAddr{ip: src_ip, port: src_port}, nil
}

func (c *UDPConn) WriteToUDP(buf: []byte, addr: *UDPAddr) (int, error) {
    c.RawSocket.SendTo(buf, addr.ip, addr.port)
}

func DialUDP(address: string, port: int, timeout_ms: int) (*UDPConn, error) {
    let sock, err = NewRawSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    if err != nil {
        return nil, err
    }

    var local_addr SockaddrInet
    local_addr.sin_family = AF_INET
    local_addr.sin_port = 0

    let errno = sys_bind(sock.fd, (*Sockaddr)(&local_addr), 16)
    if errno != 0 {
        sock.Close()
        return nil, NewSocketError(errno, "bind")
    }

    let local_ip, local_port, err = sock.GetLocalAddr()
    if err != nil {
        sock.Close()
        return nil, err
    }

    &UDPConn{
        RawSocket: sock,
        laddr: &UDPAddr{ip: local_ip, port: local_port},
        raddr: &UDPAddr{ip: address, port: port},
    }, nil
}

func ListenUDP(address: string, port: int) (*UDPListener, error) {
    let sock, err = NewRawSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    if err != nil {
        return nil, err
    }

    err = sock.UDPBind(address, port)
    if err != nil {
        sock.Close()
        return nil, err
    }

    let local_ip, local_port, err = sock.GetLocalAddr()
    if err != nil {
        sock.Close()
        return nil, err
    }

    &UDPListener{
        RawSocket: sock,
        addr: &UDPAddr{ip: local_ip, port: local_port},
    }, nil
}

struct UDPListener {
    RawSocket: *RawSocket
    addr: *UDPAddr
}

func (l *UDPListener) Close() error {
    l.RawSocket.Close()
}

func (l *UDPListener) Addr() Addr {
    l.addr
}

func (l *UDPListener) ReadFromUDP(buf: []byte) (int, *UDPAddr, error) {
    let n, src_ip, src_port, err = l.RawSocket.RecvFrom(buf)
    if err != nil {
        return n, nil, err
    }

    n, &UDPAddr{ip: src_ip, port: src_port}, nil
}

func (l *UDPListener) WriteToUDP(buf: []byte, addr: *UDPAddr) (int, error) {
    l.RawSocket.SendTo(buf, addr.ip, addr.port)
}
