package src.net

import neurx_agent.aagent

// S 语言 neurx-agent TCP 网络服务主循环（伪实现，接口演示）

func serve_neurx_agent_tcp(addr string) {
    Listener l = Listen("tcp", addr)
    if l == nil {
        print("[error] listen failed: " + addr)
        return
    }
    print("[neurx-agent] listening on " + addr)
    while true {
        Conn c = l.Accept()
        if c == nil {
            print("[error] accept failed")
            continue
        }
        // 启动协程处理连接（伪协程，实际可用线程/事件循环）
        handle_neurx_agent_conn(c)
    }
}

func handle_neurx_agent_conn(Conn c) {
    // 初始化 agent
    aagent_config cfg = aagent_config {
        name: "neurx-agent",
        model: "default",
        skills: [],
        backend_config: map[string, string]{},
    }
    aagent agent = new_aagent(cfg)
    []byte buf = make([]byte, 4096)
    while true {
        n, err = c.Read(buf)
        if err != nil || n <= 0 {
            break
        }
        // 假设消息为 utf-8 文本
        string msg = string(buf[0:n])
        aagent_message req = aagent_message {
            role: "user",
            content: msg,
            meta: map[string, string]{},
        }
        aagent_message reply = aagent_handle(agent, req)
        c.Write([]byte(reply.content))
    }
    c.Close()
}

// 启动 neurx-agent TCP 服务
func main() {
    serve_neurx_agent_tcp("0.0.0.0:8088")
}
