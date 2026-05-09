package src.net.http

struct HTTPServer {
    string addr
    map[string, func(Request, Response)] routes
}

func (s *HTTPServer) HandleFunc(string path, func(Request, Response) handler) {
    if s.routes == nil {
        s.routes = map[string, func(Request, Response)]{}
    }
    s.routes[path] = handler
}

func (s *HTTPServer) ListenAndServe() {
    print("[http] listen on " + s.addr)
}
