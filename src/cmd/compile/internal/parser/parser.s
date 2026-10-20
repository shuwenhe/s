package s

import (
    "std"
)

struct parse_error {
    string message
    int line
    int column
}

/* The historical package-s parser is not the production parser. Keep only
 * the compatibility boundary used by legacy semantic/noder callers; the
 * canonical production entry is compile.internal.parser.syntax. */
func legacy_parse_source(string source) (source_file, parse_error) {
    return source_file {}, parse_error {}
}

func legacy_parse_tokens(token[] tokens) (source_file, parse_error) {
    return source_file {}, parse_error {}
}
