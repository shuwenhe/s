package src.net.http

func (r *http_response) write(string data) {
    r.body = data
}
