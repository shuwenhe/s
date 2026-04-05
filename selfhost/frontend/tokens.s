package selfhost.frontend

pub enum TokenKind {
    Ident,
    Int,
    String,
    Keyword,
    Symbol,
    Eof,
}

pub struct Token {
    kind: TokenKind,
    value: String,
    line: i32,
    column: i32,
}

pub fn is_keyword(text: String) -> bool {
    match text {
        "package" => true,
        "use" => true,
        "as" => true,
        "pub" => true,
        "fn" => true,
        "let" => true,
        "var" => true,
        "const" => true,
        "static" => true,
        "struct" => true,
        "enum" => true,
        "trait" => true,
        "impl" => true,
        "for" => true,
        "if" => true,
        "else" => true,
        "while" => true,
        "match" => true,
        "return" => true,
        "break" => true,
        "continue" => true,
        "true" => true,
        "false" => true,
        "unsafe" => true,
        "extern" => true,
        "mut" => true,
        "where" => true,
        "in" => true,
        _ => false,
    }
}
