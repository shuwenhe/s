package src.net.http

type handler_func = func(http_request) http_response

struct route_entry {
    string method
    string path
    handler_func handler
}

struct server {
    string host
    int port
    []route_entry routes
}

func (s *server) add_route(string method, string path, handler_func handler) {
    s.routes.push(route_entry {
        method: method,
        path: path,
        handler: handler,
    })
}

func (s *server) serve() {
}
