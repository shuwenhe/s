package src.net
interface addr {
    network() string
    string() string
}

struct tcp_addr {
    ip string
    port int
}

func (a *tcp_addr) network() string {
    "tcp"
}

func (a *tcp_addr) string() string {
    a.ip + ":" + itoa(a.port)
}