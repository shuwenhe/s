package lsp

use "std"
use "../s"

struct document_manager {
    map[string, text_document] documents

    map[string, s::source_file] ast_cache

    map[string, vec[parse_error]] error_cache
}

struct parse_error {
    string message
    position pos
}

func new_document_manager() document_manager {
    document_manager {
        documents: map[string, text_document](),
        ast_cache: map[string, s::source_file](),
        error_cache: map[string, vec[parse_error]](),
    }
}

func (dm mut document_manager) open_document(item text_document_item) {
    doc := text_document {
        uri: item.uri,
        language_id: item.language_id,
        version: item.version,
        text: item.text,
    }
    dm.documents.insert(item.uri, doc)
    dm.parse_document(item.uri)
}

func (dm mut document_manager) update_document(uri string, text string, version int) {
    match dm.documents.get(uri) {
        option::some(doc) : {
            updated := text_document {
                uri: uri,
                language_id: doc.language_id,
                version: version,
                text: text,
            }
            dm.documents.insert(uri, updated)
            dm.parse_document(uri)
        },
        option::none() : {
        }
    }
}

func (dm mut document_manager) close_document(uri string) {
    dm.documents.remove(uri)
    dm.ast_cache.remove(uri)
    dm.error_cache.remove(uri)
}

func (dm document_manager) get_document(uri string) option[text_document] {
    dm.documents.get(uri)
}

func (dm document_manager) get_ast(uri string) option[s::source_file] {
    dm.ast_cache.get(uri)
}

func (dm document_manager) get_errors(uri string) option[vec[parse_error]] {
    dm.error_cache.get(uri)
}

func (dm mut document_manager) parse_document(uri string) {
    match dm.documents.get(uri) {
        option::some(doc) : {
            lexer := s::new_lexer(doc.text)
            match lexer.tokenize() {
                result::ok(tokens) : {
                    match s::parse_tokens(tokens) {
                        result::ok(ast) : {
                            dm.ast_cache.insert(uri, ast)
                            dm.error_cache.remove(uri)
                        },
                        result::err(err) : {
                            dm.error_cache.insert(uri, vec[parse_error]{
                                parse_error {
                                    message: err.message,
                                    pos: position { line: err.line, character: err.column }
                                }
                            })
                        }
                    }
                },
                result::err(err) : {
                    dm.error_cache.insert(uri, vec[parse_error]{
                        parse_error {
                            message: err.message,
                            pos: position { line: err.line, character: err.column }
                        }
                    })
                }
            }
        },
        option::none() : {
        }
    }
}

func (dm document_manager) get_token_at_position(uri string, pos position) option[string] {
    match dm.documents.get(uri) {
        option::some(doc) : {
            lines := std::split(doc.text, "\n")
            if pos.line < lines.len() {
                line := lines[pos.line]
                if pos.character < line.len() {
                    start := pos.character
                    end := pos.character

                    while start > 0 && is_identifier_char(line[start - 1]) {
                        start = start - 1
                    }

                    while end < line.len() && is_identifier_char(line[end]) {
                        end = end + 1
                    }

                    if start < end {
                        option::some(line.substring(start, end))
                    } else {
                        option::none()
                    }
                } else {
                    option::none()
                }
            } else {
                option::none()
            }
        },
        option::none() : option::none()
    }
}

func is_identifier_char(c str) bool {
    (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || 
    (c >= "0" && c <= "9") || c == "_"
}

func (dm document_manager) get_document_symbols(uri string) option[vec[document_symbol]] {
    match dm.get_ast(uri) {
        option::some(ast) : option::some(extract_symbols_from_ast(ast)),
        option::none() : option::none()
    }
}

func extract_symbols_from_ast(ast s::source_file) vec[document_symbol] {
    symbols := vec[document_symbol]()

    i := 0
    while i < ast.items.len() {
        item := ast.items[i]
        match item {
            s::item::function(func) : {
                symbols.push(document_symbol {
                    name: func.sig.name,
                    kind: symbol_kind::function_k,
                    range_val: range {
                        start: position { line: func.line, character: 0 },
                        end: position { line: func.line, character: func.sig.name.len() }
                    },
                    selection_range: range {
                        start: position { line: func.line, character: 0 },
                        end: position { line: func.line, character: func.sig.name.len() }
                    },
                    children: option::none(),
                    deprecated: option::none()
                })
            },
            s::item::struct(s_decl) : {
                symbols.push(document_symbol {
                    name: s_decl.name,
                    kind: symbol_kind::struct_k,
                    range_val: range {
                        start: position { line: s_decl.line, character: 0 },
                        end: position { line: s_decl.line, character: s_decl.name.len() }
                    },
                    selection_range: range {
                        start: position { line: s_decl.line, character: 0 },
                        end: position { line: s_decl.line, character: s_decl.name.len() }
                    },
                    children: option::none(),
                    deprecated: option::none()
                })
            },
            s::item::enum(e_decl) : {
                symbols.push(document_symbol {
                    name: e_decl.name,
                    kind: symbol_kind::enum_k,
                    range_val: range {
                        start: position { line: e_decl.line, character: 0 },
                        end: position { line: e_decl.line, character: e_decl.name.len() }
                    },
                    selection_range: range {
                        start: position { line: e_decl.line, character: 0 },
                        end: position { line: e_decl.line, character: e_decl.name.len() }
                    },
                    children: option::none(),
                    deprecated: option::none()
                })
            },
            s::item::trait(t_decl) : {
                symbols.push(document_symbol {
                    name: t_decl.name,
                    kind: symbol_kind::interface_k,
                    range_val: range {
                        start: position { line: t_decl.line, character: 0 },
                        end: position { line: t_decl.line, character: t_decl.name.len() }
                    },
                    selection_range: range {
                        start: position { line: t_decl.line, character: 0 },
                        end: position { line: t_decl.line, character: t_decl.name.len() }
                    },
                    children: option::none(),
                    deprecated: option::none()
                })
            },
            _ : {}
        }
        i = i + 1
    }

    symbols
}
