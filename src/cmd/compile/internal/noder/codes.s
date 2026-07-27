package compile.internal.noder

func code_ok() string {
    "E0000"
}

func code_read_failed() string {
    "E7001"
}

func code_lex_failed() string {
    "E7002"
}

func code_parse_failed() string {
    "E7003"
}

func code_write_failed() string {
    "E7004"
}

func code_invalid_import() string {
    "E7005"
}

func code_unknown_quirk() string {
    "E7006"
}

func severity(string code) string {
    if code == code_ok() {
        return "ok"
    }
    if code == code_unknown_quirk() {
        return "warning"
    }
    "error"
}
