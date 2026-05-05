package src.net

// ParseError 错误类型
struct ParseError {
    string typ
    string text
}
func (e *ParseError) Error() string {
    "invalid " + e.typ + ": " + e.text
}

// AddrError 错误类型
struct AddrError {
    string err
    string addr
}
func (e *AddrError) Error() string {
    if e == nil {
        return "<nil>"
    }
    s = e.err
    if e.addr != "" {
        s = "address " + e.addr + ": " + s
    }
    s
}

// UnknownNetworkError 错误类型
struct UnknownNetworkError {
    string net
}
func (e *UnknownNetworkError) Error() string {
    "unknown network " + e.net
}

// timeoutError 错误类型
struct timeoutError {}
func (e *timeoutError) Error() string { "i/o timeout" }

// OpError 错误类型
struct OpError {
    string op
    string net
    Addr source
    Addr addr
    string err
}
func (e *OpError) Error() string {
    if e == nil {
        return "<nil>"
    }
    s = e.op
    if e.net != "" {
        s = s + " " + e.net
    }
    if e.source != nil {
        s = s + " " + e.source.String()
    }
    if e.addr != nil {
        if e.source != nil {
            s = s + "->"
        } else {
            s = s + " "
        }
        s = s + e.addr.String()
    }
    s = s + ": " + e.err
    s
}
