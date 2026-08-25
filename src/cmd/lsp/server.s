package main

use "std"
use "../lsp"

struct lsp_server {
    handler: lsp::lsp_handler
    initialized: bool
}

func main() {
    server := lsp_server {
        handler: lsp::new_lsp_handler(),
        initialized: false,
    }

    server.run()
}

func (server lsp_server) run() {
    buf := ""
    loop {
        switch std::read_line_from_stdin() {
            result::ok(line) : {
                if line == "" {
                    break
                }

                prefix := "Content-Length: "
                if std::starts_with(line, prefix) {
                    len_str := line.substring(prefix.len(), line.len())
                    switch std::parse_int(len_str) {
                        result::ok(content_len) : {
                            switch std::read_bytes_from_stdin(content_len) {
                                result::ok(content) : {
                                    server.handle_message(content)
                                },
                                result::err(_) : {
                                }
                            }
                        },
                        result::err(_) : {}
                    }
                }
            },
            result::err(_) : {
                break
            }
        }
    }
}

func (server lsp_server) handle_message(message string) {
    switch lsp::parse_jsonrpc_message(message) {
        result::ok(req) : {
            switch req.method {
                "initialize" : server.handle_initialize(req),
                "initialized" : {},
                "shutdown" : server.handle_shutdown(req),
                "exit" : std::exit(0),

                "textDocument/didOpen" : server.handle_did_open(req, message),
                "textDocument/didChange" : server.handle_did_change(req, message),
                "textDocument/didSave" : server.handle_did_save(req, message),
                "textDocument/didClose" : server.handle_did_close(req, message),

                "textDocument/completion" : server.handle_completion(req, message),
                "textDocument/hover" : server.handle_hover(req, message),
                "textDocument/definition" : server.handle_definition(req, message),
                "textDocument/references" : server.handle_references(req, message),
                "textDocument/documentSymbol" : server.handle_document_symbol(req, message),
                "textDocument/rename" : server.handle_rename(req, message),
                "workspace/symbol" : server.handle_workspace_symbol(req, message),

                _ : {
                    switch req.id {
                        option::some(id) : {
                            server.send_error(id, -32601, "Method not found")
                        },
                        option::none() : {}
                    }
                }
            }
        },
        result::err(err) : {
            std::println("LSP Parse Error: " + err)
        }
    }
}

func (server lsp_server) handle_initialize(req lsp::jsonrpc_request) {
    server.initialized = true

    switch req.id {
        option::some(id) : {
            capabilities := lsp::server_capabilities {
                text_document_sync: true,
                completion_provider: true,
                hover_provider: true,
                definition_provider: true,
                references_provider: true,
                document_symbol_provider: true,
                rename_provider: true,
                workspace_symbol_provider: false,
            }

            result := "{\"capabilities\":{" +
                "\"textDocumentSync\":true," +
                "\"completionProvider\":true," +
                "\"hoverProvider\":true," +
                "\"definitionProvider\":true," +
                "\"referencesProvider\":true," +
                "\"documentSymbolProvider\":true," +
                "\"renameProvider\":true," +
                "\"serverInfo\":{\"name\":\"s-lsp\",\"version\":\"1.0.0\"}" +
                "}}"

            server.send_response(id, result)
        },
        option::none() : {}
    }
}

func (server lsp_server) handle_shutdown(req lsp::jsonrpc_request) {
    switch req.id {
        option::some(id) : server.send_response(id, "null"),
        option::none() : {}
    }
}

func (server lsp_server) handle_did_open(req lsp::jsonrpc_request, message string) {
    switch extract_text_document_item(message) {
        option::some(item) : {
            params := lsp::did_open_text_document_params {
                text_document: item,
            }
            server.handler.on_did_open(params)

            server.send_diagnostics(item.uri)
        },
        option::none() : {}
    }
}

func (server lsp_server) handle_did_change(req lsp::jsonrpc_request, message string) {
    switch extract_did_change_params(message) {
        option::some((uri, text, version)) : {
            changes := vec[lsp::text_document_content_change_event]{
                lsp::text_document_content_change_event {
                    range_val: option::none(),
                    text: text,
                }
            }

            params := lsp::did_change_text_document_params {
                text_document: lsp::versioned_text_document_identifier {
                    uri: uri,
                    version: version,
                },
                content_changes: changes,
            }

            server.handler.on_did_change(params)

            server.send_diagnostics(uri)
        },
        option::none() : {}
    }
}

func (server lsp_server) handle_did_save(req lsp::jsonrpc_request, message string) {
    switch extract_text_document_identifier(message) {
        option::some(uri) : {
            params := lsp::did_save_text_document_params {
                text_document: lsp::text_document_identifier { uri: uri },
                text: option::none(),
            }
            server.handler.on_did_save(params)
        },
        option::none() : {}
    }
}

func (server lsp_server) handle_did_close(req lsp::jsonrpc_request, message string) {
    switch extract_text_document_identifier(message) {
        option::some(uri) : {
            params := lsp::did_close_text_document_params {
                text_document: lsp::text_document_identifier { uri: uri },
            }
            server.handler.on_did_close(params)
        },
        option::none() : {}
    }
}

func (server lsp_server) handle_completion(req lsp::jsonrpc_request, message string) {
    switch req.id {
        option::some(id) : {
            switch extract_position_params(message) {
                option::some((uri, line, character)) : {
                    pos := lsp::position { line: line, character: character }
                    completions := server.handler.get_completions(uri, pos)
                    result := lsp::serialize_completion_list(completions)
                    server.send_response(id, result)
                },
                option::none() : server.send_error(id, -32700, "Invalid parameters")
            }
        },
        option::none() : {}
    }
}

func (server lsp_server) handle_hover(req lsp::jsonrpc_request, message string) {
    switch req.id {
        option::some(id) : {
            switch extract_position_params(message) {
                option::some((uri, line, character)) : {
                    pos := lsp::position { line: line, character: character }
                    switch server.handler.get_hover(uri, pos) {
                        option::some(hover) : {
                            result := lsp::serialize_hover(hover)
                            server.send_response(id, result)
                        },
                        option::none() : server.send_response(id, "null")
                    }
                },
                option::none() : server.send_error(id, -32700, "Invalid parameters")
            }
        },
        option::none() : {}
    }
}

func (server lsp_server) handle_definition(req lsp::jsonrpc_request, message string) {
    switch req.id {
        option::some(id) : {
            switch extract_position_params(message) {
                option::some((uri, line, character)) : {
                    pos := lsp::position { line: line, character: character }
                    switch server.handler.find_symbol_definition(uri, "") {
                        option::some(symbol) : {
                            location := "{\"uri\":\"" + uri + "\",\"range\":" + 
                                lsp::serialize_range(symbol.range_val) + "}"
                            server.send_response(id, location)
                        },
                        option::none() : server.send_response(id, "null")
                    }
                },
                option::none() : server.send_error(id, -32700, "Invalid parameters")
            }
        },
        option::none() : {}
    }
}

func (server lsp_server) handle_references(req lsp::jsonrpc_request, message string) {
    switch req.id {
        option::some(id) : {
            server.send_response(id, "[]")
        },
        option::none() : {}
    }
}

func (server lsp_server) handle_document_symbol(req lsp::jsonrpc_request, message string) {
    switch req.id {
        option::some(id) : {
            switch extract_text_document_identifier(message) {
                option::some(uri) : {
                    symbols := server.handler.get_document_symbols(uri)
                    result := lsp::serialize_document_symbols(symbols)
                    server.send_response(id, result)
                },
                option::none() : server.send_error(id, -32700, "Invalid parameters")
            }
        },
        option::none() : {}
    }
}

func (server lsp_server) handle_rename(req lsp::jsonrpc_request, message string) {
    switch req.id {
        option::some(id) : {
            server.send_response(id, "{\"changes\":{}}")
        },
        option::none() : {}
    }
}

func (server lsp_server) handle_workspace_symbol(req lsp::jsonrpc_request, message string) {
    switch req.id {
        option::some(id) : {
            server.send_response(id, "[]")
        },
        option::none() : {}
    }
}

func (server lsp_server) send_diagnostics(uri string) {
    diags := server.handler.publish_diagnostics(uri)
    diag_json := lsp::serialize_diagnostics(diags)
    message := lsp::create_notification(
        "textDocument/publishDiagnostics",
        "{\"uri\":\"" + uri + "\",\"diagnostics\":" + diag_json + "}"
    )
    server.send_notification(message)
}

func (server lsp_server) send_response(id int, result string) {
    response := lsp::create_response(id, result)
    server.send_message(response)
}

func (server lsp_server) send_error(id int, code int, message string) {
    response := lsp::create_error_response(id, code, message)
    server.send_message(response)
}

func (server lsp_server) send_notification(message string) {
    server.send_message(message)
}

func (server lsp_server) send_message(message string) {
    header := "Content-Length: " + std::to_string(message.len()) + "\r\n\r\n"
    std::print(header)
    std::print(message)
}

func extract_text_document_item(message string) option[lsp::text_document_item] {
    switch extract_text_document_identifier(message) {
        option::some(uri) : {
            option::none()
        },
        option::none() : option::none()
    }
}

func extract_text_document_identifier(message string) option[string] {
    lsp::extract_json_string(message, "uri")
}

func extract_position_params(message string) option[(string, int, int)] {
    switch lsp::extract_json_string(message, "uri") {
        option::some(uri) : {
            switch lsp::extract_json_string(message, "line") {
                option::some(line_str) : {
                    switch std::parse_int(line_str) {
                        result::ok(line) : {
                            switch lsp::extract_json_string(message, "character") {
                                option::some(char_str) : {
                                    switch std::parse_int(char_str) {
                                        result::ok(character) : {
                                            option::some((uri, line, character))
                                        },
                                        result::err(_) : option::none()
                                    }
                                },
                                option::none() : option::none()
                            }
                        },
                        result::err(_) : option::none()
                    }
                },
                option::none() : option::none()
            }
        },
        option::none() : option::none()
    }
}

func extract_did_change_params(message string) option[(string, string, int)] {
    switch lsp::extract_json_string(message, "uri") {
        option::some(uri) : {
            switch lsp::extract_json_string(message, "text") {
                option::some(text) : {
                    switch lsp::extract_json_string(message, "version") {
                        option::some(version_str) : {
                            switch std::parse_int(version_str) {
                                result::ok(version) : {
                                    option::some((uri, text, version))
                                },
                                result::err(_) : option::none()
                            }
                        },
                        option::none() : option::none()
                    }
                },
                option::none() : option::none()
            }
        },
        option::none() : option::none()
    }
}
