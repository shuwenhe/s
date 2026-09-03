package lsp
use "std"
struct lsp_handler {
    doc_manager: document_manager
}

func new_lsp_handler() lsp_handler {
    lsp_handler {
        doc_manager: new_document_manager(),
    }
}

func (h lsp_handler) on_did_open(params did_open_text_document_params) {
    h.doc_manager.open_document(params.text_document)
}

func (h lsp_handler) on_did_change(params did_change_text_document_params) {
    uri := params.text_document.uri
    version := params.text_document.version
    switch h.doc_manager.get_document(uri) {
        option::some(doc) : {
            new_text := apply_content_changes(doc.text, params.content_changes)
            h.doc_manager.update_document(uri, new_text, version)
        },
        option::none() : {}
    }
}

func (h lsp_handler) on_did_save(params did_save_text_document_params) {
}

func (h lsp_handler) on_did_close(params did_close_text_document_params) {
    h.doc_manager.close_document(params.text_document.uri)
}

func (h lsp_handler) publish_diagnostics(uri string) diagnostic[] {
    diags := diagnostic[]()
    switch h.doc_manager.get_errors(uri) {
        option::some(errors) : {
            i := 0
            for i < len(errors) {
                err := errors[i]
                diags.push(diagnostic {
                    r: range {
                        start: err.pos, end position { line: err.pos.line, character err.pos.character + 1 }
                    }, message err.message, severity option::some(1), code option::some("S000"), source option::some("s-lsp"), related_information option::none()
                })
                i = i + 1
            }
        },
        option::none() : {}
    }
    diags
}

func (h lsp_handler) get_document_symbols(uri string) document_symbol[] {
    switch h.doc_manager.get_document_symbols(uri) {
        option::some(symbols) : symbols,
        option::none() : document_symbol[]()
    }
}

func (h lsp_handler) get_completions(uri string, pos position) completion_list {
    completions := completion_item[]()
    completions.append(get_keyword_completions())
    switch h.doc_manager.get_document_symbols(uri) {
        option::some(symbols) : {
            i := 0
            for i < len(symbols) {
                sym := symbols[i]
                completions.push(completion_item {
                    label: sym.name, kind option::some(symbol_kind_to_completion_kind(sym.kind)), detail option::some(format_symbol_kind(sym.kind)), documentation option::some("Defined in current file"), sort_text option::some("1_" + sym.name), filter_text option::some(sym.name), text_edit_text option::none(), deprecated option::none(), score option::some(50),
                })
                i = i + 1
            }
        },
        option::none() : {}
    }
    completion_list {
        is_incomplete: false, items completions,
    }
}

func get_keyword_completions() completion_item[] {
    keywords := []string{
        "package", "use", "pub", "func", "struct", "enum", "trait",
        "const", "static", "if", "else", "for", "while", "switch",
        "case", "default", "return", "break", "continue", "true", "false",
        "nil", "let", "var", "in", "as",
    }
    completions := completion_item[]()
    i := 0
    for i < len(keywords) {
        completions.push(completion_item {
            label: keywords[i], kind option::some(completion_item_kind::keyword), detail option::some("Keyword"), documentation option::none(), sort_text option::some("0_" + keywords[i]), filter_text option::some(keywords[i]), text_edit_text option::none(), deprecated option::none(), score option::some(100),
        })
        i = i + 1
    }
    completions
}

func (h lsp_handler) get_hover(uri string, pos position) option[hover] {
    switch h.doc_manager.get_token_at_position(uri, pos) {
        option::some(token) : {
            switch h.find_symbol_definition(uri, token) {
                option::some(symbol) : {
                    option::some(hover {
                        contents: format_hover_contents(symbol), r option::some(range {
                            start: pos, end position { line: pos.line, character pos.character + len(token) }
                        })
                    })
                },
                option::none() : {
                    option::some(hover {
                        contents: "**" + token + "**", r option::some(range {
                            start: pos, end position { line: pos.line, character pos.character + len(token) }
                        })
                    })
                }
            }
        },
        option::none() : option::none()
    }
}

func (h lsp_handler) find_symbol_definition(uri string, name string) option[document_symbol] {
    switch h.doc_manager.get_document_symbols(uri) {
        option::some(symbols) : find_symbol_in_list(symbols, name),
        option::none() : option::none()
    }
}

func find_symbol_in_list(symbols document_symbol[], name string) option[document_symbol] {
    i := 0
    for i < len(symbols) {
        if symbols[i].name == name {
            return option::some(symbols[i]
        }
        i = i + 1
    }
    option::none()
}

func apply_content_changes(text string, changes text_document_content_change_event[]) string {
    result := text
    i := 0
    for i < len(changes) {
        change := changes[i]
        switch change.range_val {
            option::some(r) : {
                lines := std::split(result, "\n")
                start_offset := position_to_offset(lines, r.start)
                end_offset := position_to_offset(lines, r.end)
                before := result.substring(0, start_offset)
                after := result.substring(end_offset, len(result))
                result = before + change.text + after
            },
            option::none() : {
                result = change.text
            }
        }
        i = i + 1
    }
    result
}

func position_to_offset(lines []string, pos position) int {
    offset := 0
    i := 0
    for i < pos.line && i < len(lines) {
        offset = offset + lines[i].len() + 1
        i = i + 1
    }
    if pos.line < len(lines) {
        offset = offset + pos.character
    }
    offset
}

func symbol_kind_to_completion_kind(kind symbol_kind) completion_item_kind {
    switch kind {
        symbol_kind::function_k : completion_item_kind::function,
        symbol_kind::struct_k : completion_item_kind::struct_k,
        symbol_kind::enum_k : completion_item_kind::enum_value,
        symbol_kind::interface_k : completion_item_kind::interface,
        symbol_kind::variable_k : completion_item_kind::variable,
        symbol_kind::constant_k : completion_item_kind::constant,
        symbol_kind::method_k : completion_item_kind::method,
        symbol_kind::field_k : completion_item_kind::field,
        _ : completion_item_kind::text,
    }
}

func format_symbol_kind(kind symbol_kind) string {
    switch kind {
        symbol_kind::function_k : "function",
        symbol_kind::struct_k : "struct",
        symbol_kind::enum_k : "enum",
        symbol_kind::interface_k : "interface",
        symbol_kind::variable_k : "variable",
        symbol_kind::constant_k : "constant",
        symbol_kind::method_k : "method",
        symbol_kind::field_k : "field",
        _ : "symbol",
    }
}

func format_hover_contents(symbol document_symbol) string {
    kind_str := format_symbol_kind(symbol.kind)
    "**" + kind_str + "** `" + symbol.name + "`"
}
