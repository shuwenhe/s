package src.net

interface Addr {
    Network() string
    String() string
}

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
