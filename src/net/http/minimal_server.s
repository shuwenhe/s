package src.net.http
type handler_func = func(http_request) http_response
struct route_entry {
    method string
    path string
    handler handler_func
}

struct server {
    host string
    port int
    route_entry[] routes
}

func (s *server) add_route(string method, string path, handler_func handler) {
    s.routes.push(route_entry {
        method: method, path path, handler handler,
    })
}

func (s *server) serve() {
}