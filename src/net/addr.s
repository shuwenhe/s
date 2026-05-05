package src.net

// Addr 接口
interface Addr {
    Network() string
    String() string
}

// TCPAddr 示例实现
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
