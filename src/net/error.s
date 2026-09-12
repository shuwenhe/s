package src.net
struct parse_error {
    typ string
    text string
}

func (e *parse_error) error() string {
    "invalid " + e.typ + ": " + e.text
}

struct addr_error {
    err string
    addr string
}

func (e *addr_error) error() string {
    if e == nil {
        return "<nil>"
    }
    s = e.err
    if e.addr != "" {
        s = "address " + e.addr + ": " + s
    }
    s
}

struct unknown_network_error {
    net string
}

func (e *unknown_network_error) error() string {
    "unknown network " + e.net
}

struct timeout_error {}

func (e *timeout_error) error() string { "i/o timeout" }

struct op_error {
    op string
    net string
    source addr
    addr addr
    err string
}

func (e *op_error) error() string {
    if e == nil {
        return "<nil>"
    }
    s = e.op
    if e.net != "" {
        s = s + " " + e.net
    }
    if e.source != nil {
        s = s + " " + e.source.string()
    }
    if e.addr != nil {
        if e.source != nil {
            s = s + "->"
        } else {
            s = s + " "
        }
        s = s + e.addr.string()
    }
    s = s + ": " + e.err
    s
}