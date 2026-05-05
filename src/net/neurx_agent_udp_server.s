package src.net

import neurx_agent.aagent

// S 语言 neurx-agent UDP 服务主循环（伪实现，接口演示）

func serve_neurx_agent_udp(addr string) {
    Listener l = Listen("udp", addr)
    if l == nil {
        print("[error] udp listen failed: " + addr)
        return
    }
    print("[neurx-agent] udp listening on " + addr)
    UDPListener ul = (UDPListener)l
    UDPConn c = UDPConn { fd: ul.fd, laddr: ul.laddr, raddr: UDPAddr{} }
    []byte buf = make([]byte, 4096)
    while true {
        n, _ = c.Read(buf)
        if n <= 0 {
            continue
        }
        string msg = string(buf[0:n])
        aagent_config cfg = aagent_config {
            name: "neurx-agent",
            model: "default",
            skills: [],
            backend_config: map[string, string]{},
        }
        aagent agent = new_aagent(cfg)
        aagent_message req = aagent_message {
            role: "user",
            content: msg,
            meta: map[string, string]{},
        }
        aagent_message reply = aagent_handle(agent, req)
        c.Write([]byte(reply.content))
    }
    l.Close()
}

func main() {
    serve_neurx_agent_udp("0.0.0.0:8090")
}
