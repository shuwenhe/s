package src.net.http

struct request {
    string method
    string path
    map[string, string] headers
    string body
}

struct response {
    int status
    map[string, string] headers
    string body
}

type handler_func = func(request) response

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
