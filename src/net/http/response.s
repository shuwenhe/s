package src.net.http

struct response {
    string body
    int status
    map[string, string] headers
}

func (r *response) write(string data) {
    r.body = data
}
