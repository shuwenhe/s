package src.net.http

struct Request {
    string method
    string path
    map[string, string] headers
    string body
}

func (r *Request) Body() string {
    r.body
}
