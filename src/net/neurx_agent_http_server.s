package src.net

import neurx_agent.aagent

// S 语言 neurx-agent HTTP 服务主循环（伪实现，接口演示）
// 依赖 minimal_server.s 的 HTTP server 骨架

func serve_neurx_agent_http(addr string) {
    // 假设有 HTTPServer/Request/Response 伪接口
    HTTPServer srv = HTTPServer { addr: addr }
    srv.HandleFunc("/agent", handle_neurx_agent_http)
    srv.ListenAndServe()
}

func handle_neurx_agent_http(Request req, Response resp) {
    // 读取请求体
    string msg = req.Body()
    aagent_config cfg = aagent_config {
        name: "neurx-agent",
        model: "default",
        skills: [],
        backend_config: map[string, string]{},
    }
    aagent agent = new_aagent(cfg)
    aagent_message areq = aagent_message {
        role: "user",
        content: msg,
        meta: map[string, string]{},
    }
    aagent_message reply = aagent_handle(agent, areq)
    resp.Write(reply.content)
}

func main() {
    serve_neurx_agent_http("0.0.0.0:8080")
}
