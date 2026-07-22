package src.net

import "src.net.internal"

struct TCPAddr {
    string ip
    int port
}

func (a *TCPAddr) Network() string {
    "tcp"
}

func (a *TCPAddr) String() string {
    a.ip + ":" + itoa(a.port)
}

struct TCPConn {
    *internal.RawSocket
    laddr *TCPAddr
    raddr *TCPAddr
}

func (c *TCPConn) Read(buf []byte) (int, error) {
    if c.RawSocket == nil {
        return 0, "connection closed"
    }
    c.RawSocket.Read(buf)
}

func (c *TCPConn) Write(buf []byte) (int, error) {
    if c.RawSocket == nil {
        return 0, "connection closed"
    }
    c.RawSocket.Write(buf)
}

func (c *TCPConn) Close() error {
    if c.RawSocket == nil {
        return "already closed"
    }
    c.RawSocket.Close()
}

func (c *TCPConn) LocalAddr() Addr {
    c.laddr
}

func (c *TCPConn) RemoteAddr() Addr {
    c.raddr
}

func (c *TCPConn) ReadFrom(buf []byte) (int, Addr, error) {
    0, nil, "tcp does not support ReadFrom"
}

func (c *TCPConn) WriteTo(buf []byte, addr Addr) (int, error) {
    0, "tcp does not support WriteTo"
}

func (c *TCPConn) SetDeadline(deadline_ns i64) error {
    if c.RawSocket == nil {
        return "connection closed"
    }

    err1 := c.SetReadDeadline(deadline_ns)
    err2 := c.SetWriteDeadline(deadline_ns)

    if err1 != nil {
        return err1
    }
    err2
}

func (c *TCPConn) SetReadDeadline(deadline_ns i64) error {
    if c.RawSocket == nil {
        return "connection closed"
    }
    c.RawSocket.SetReadDeadline(deadline_ns)
}

func (c *TCPConn) SetWriteDeadline(deadline_ns i64) error {
    if c.RawSocket == nil {
        return "connection closed"
    }
    c.RawSocket.SetWriteDeadline(deadline_ns)
}

func (c *TCPConn) SetNoDelay(on bool) error {
    if c.RawSocket == nil {
        return "connection closed"
    }
    c.RawSocket.SetTCPNoDelay(on)
}

func (c *TCPConn) SetReuseAddr(on bool) error {
    if c.RawSocket == nil {
        return "connection closed"
    }
    c.RawSocket.SetReuseAddr(on)
}

func (c *TCPConn) SetReusePort(on bool) error {
    if c.RawSocket == nil {
        return "connection closed"
    }
    c.RawSocket.SetReusePort(on)
}

func DialTCP(address string, port int, timeout_ms int) (*TCPConn, error) {
    sock, err := internal.NewRawSocket(
        internal.AF_INET,
        internal.SOCK_STREAM,
        internal.IPPROTO_TCP,
    )
    if err != nil {
        return nil, err
    }

    err = sock.Connect(address, port, timeout_ms)
    if err != nil {
        sock.Close()
        return nil, err
    }

    local_ip, local_port, _ := sock.GetLocalAddr()
    remote_ip, remote_port, _ := sock.GetRemoteAddr()

    &TCPConn{
        RawSocket: sock,
        laddr: &TCPAddr{ip: local_ip, port: local_port},
        raddr: &TCPAddr{ip: remote_ip, port: remote_port},
    }, nil
}

struct TCPListener {
    *internal.RawSocket
    addr *TCPAddr
}

func ListenTCP(address string, port int) (*TCPListener, error) {
    sock, err := internal.NewRawSocket(
        internal.AF_INET,
        internal.SOCK_STREAM,
        internal.IPPROTO_TCP,
    )
    if err != nil {
        return nil, err
    }

    sock.SetReuseAddr(true)

    err = sock.Bind(address, port)
    if err != nil {
        sock.Close()
        return nil, err
    }

    err = sock.Listen(128)
    if err != nil {
        sock.Close()
        return nil, err
    }

    &TCPListener{
        RawSocket: sock,
        addr: &TCPAddr{ip: address, port: port},
    }, nil
}

func (l *TCPListener) Accept() (*TCPConn, error) {
    if l.RawSocket == nil {
        return nil, "listener closed"
    }

    client_sock, err := l.RawSocket.Accept()
    if err != nil {
        return nil, err
    }

    remote_ip, remote_port, _ := client_sock.GetRemoteAddr()
    local_ip, local_port, _ := client_sock.GetLocalAddr()

    &TCPConn{
        RawSocket: client_sock,
        laddr: &TCPAddr{ip: local_ip, port: local_port},
        raddr: &TCPAddr{ip: remote_ip, port: remote_port},
    }, nil
}

func (l *TCPListener) Close() error {
    if l.RawSocket == nil {
        return "already closed"
    }
    l.RawSocket.Close()
}

func (l *TCPListener) Addr() Addr {
    l.addr
}
