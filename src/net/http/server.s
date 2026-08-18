package src.net.http

struct HTTPServer {
    string addr
    map[string, func(http_request, http_response)] routes
}
func (s *HTTPServer) HandleFunc(string path, func(http_request, http_response) handler) {
    if s.routes == nil {
        s.routes = map[string, func(http_request, http_response)]{}
    }
    s.routes[path] = handler
}
func (s *HTTPServer) ListenAndServe() {
    print("[http] listen on " + s.addr)
}
