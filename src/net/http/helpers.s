package src.net.http

use std.conv.int_to_string

struct http_request {
    string method
    string path
    []string headers
    string body
}

struct http_response {
    int status_code
    []string headers
    string body
}

func split_http_string(string s, string sep) []string {
    result := []string{}
    if len(s) == 0 { return result }
    current := ""
    for i := 0; i < len(s); i++ {
        current = current + string(s[i])
        if i+len(sep) <= len(s) && s[i:i+len(sep)] == sep {
            if len(current) > len(sep) {
                result = append(result, current[0:len(current)-len(sep)])
            } else {
                result = append(result, "")
            }
            current = ""
            i = i + len(sep) - 1
        }
    }
    if len(current) > 0 {
        result = append(result, current)
    }
    result
}

func parse_http_request(string raw_request) http_request {
    lines := split_http_string(raw_request, "\n")
    if len(lines) == 0 {
        return http_request{method: "", path: "/", headers: [], body: ""}
    }
    request_line := lines[0]
    parts := split_http_string(request_line, " ")
    method := ""
    path := "/"
    if len(parts) >= 2 {
        method = parts[0]
        path = parts[1]
    }
    headers := []string{}
    body_start := 0
    for i := 1; i < len(lines); i++ {
        line := lines[i]
        if len(line) == 0 {
            body_start = i + 1
            break
        }
        headers = append(headers, line)
    }
    body := ""
    if body_start < len(lines) {
        body = lines[body_start]
    }
    http_request{
        method: method,
        path: path,
        headers: headers,
        body: body,
    }
}

func format_http_response(http_response resp) string {
    response := "HTTP/1.1 " + int_to_string(resp.status_code) + " OK\r\n"
    response = response + "Content-Type: application/json\r\n"
    response = response + "Content-Length: " + int_to_string(len(resp.body)) + "\r\n"
    response = response + "Connection: close\r\n"
    for i := 0; i < len(resp.headers); i++ {
        response = response + resp.headers[i] + "\r\n"
    }
    response = response + "\r\n" + resp.body
    response
}