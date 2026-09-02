package src.net
interface addr {
    network() string
    string() string
}
struct tcp_addr {
    string ip
    int port
}

func (a *tcp_addr) network() string {
    "tcp"
}

func (a *tcp_addr) string() string {
    a.ip + ":" + itoa(a.port)
}
