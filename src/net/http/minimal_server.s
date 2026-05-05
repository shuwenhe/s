package src.net.http

// 最小 HTTP 服务端实现（伪代码/接口骨架，需 S 运行时 socket/IO 支持）

struct Request {
    string method
    string path
    map[string, string] headers
    string body
}

struct Response {
    int status
    map[string, string] headers
    string body
}

type HandlerFunc = func(Request) Response

struct route_entry {
    string method
    string path
    HandlerFunc handler
}

struct Server {
    string host
    int port
    []route_entry routes
}

func (s *Server) add_route(string method, string path, HandlerFunc handler) {
    s.routes.push(route_entry {
        method: method,
        path: path,
        handler: handler,
    })
}

// 监听端口并处理请求（伪实现，需 S socket/IO 支持）
func (s *Server) serve() {
    // 1. 监听 s.host:s.port
    // 2. 循环接受连接，解析 HTTP 请求
    // 3. 路由分发到 handler
    // 4. handler 返回 Response，写回 HTTP 响应
    // 这里只给出接口和伪流程，具体 socket/IO 需 S 运行时支持
}
