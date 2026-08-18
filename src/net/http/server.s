package src.net.http

struct http_server {
    string addr
    map[string, func(http_request, http_response)] routes
}
func (http_server* s) handle_func(string path, func(http_request, http_response) handler) {
    if s.routes == nil {
        s.routes = map[string, func(http_request, http_response)]{}
    }
    s.routes[path] = handler
}
func (http_server* s) listen_and_serve() {
    print("[http] listen on " + s.addr)
}
