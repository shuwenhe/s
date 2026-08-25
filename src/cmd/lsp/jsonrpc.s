package lsp

use "std"

struct jsonrpc_request {
    string jsonrpc
    string method
    option[map[string, string]] params
    option[int] id
}

struct jsonrpc_response {
    string jsonrpc
    option[string] result
    option[string] error_msg
    option[int] id
}

struct jsonrpc_notification {
    string jsonrpc
    string method
    option[map[string, string]] params
}

func parse_jsonrpc_message(raw string) (jsonrpc_request, string) {
    switch extract_json_string(raw, "method") {
        option::some(method) : {
            id_str := extract_json_string(raw, "id")
            params := extract_json_string(raw, "params")

            id_opt := option::none()
            switch id_str {
                option::some(id_val) : {
                    switch std::parse_int(id_val) {
                        id_num : id_opt = option::some(id_num),
                        _ : {}
                    }
                },
                option::none() : {}
            }

            jsonrpc_request {
                jsonrpc: "2.0",
                method: method,
                params: option::none(),
                id: id_opt,
            }
        },
        option::none() : {
            "No method field in request"
        }
    }
}

func create_response(id int, result string) string {
    "{\"jsonrpc\":\"2.0\",\"id\":" + std::to_string(id) + ",\"result\":" + result + "}"
}

func create_error_response(id int, code int, message string) string {
    "{\"jsonrpc\":\"2.0\",\"id\":" + std::to_string(id) + 
    ",\"error\":{\"code\":" + std::to_string(code) + ",\"message\":\"" + escape_json_string(message) + "\"}}"
}

func create_notification(method string, params string) string {
    "{\"jsonrpc\":\"2.0\",\"method\":\"" + method + "\",\"params\":" + params + "}"
}

func serialize_diagnostics(diags vec[diagnostic]) string {
    var result = "["
    var i = 0
    for i < diags.len() {
        if i > 0 {
            result = result + ","
        }
        result = result + serialize_diagnostic(diags[i])
        i = i + 1
    }
    result = result + "]"
    result
}

func serialize_diagnostic(d diagnostic) string {
    "{\"range\":" + serialize_range(d.r) + 
    ",\"message\":\"" + escape_json_string(d.message) + 
    "\",\"severity\":" + serialize_severity(d.severity) + "}"
}

func serialize_document_symbols(symbols vec[document_symbol]) string {
    var result = "["
    var i = 0
    for i < symbols.len() {
        if i > 0 {
            result = result + ","
        }
        result = result + serialize_document_symbol(symbols[i])
        i = i + 1
    }
    result = result + "]"
    result
}

func serialize_document_symbol(symbol document_symbol) string {
    "{\"name\":\"" + escape_json_string(symbol.name) + 
    "\",\"kind\":" + std::to_string(symbol_kind_to_int(symbol.kind)) +
    ",\"range\":" + serialize_range(symbol.range_val) +
    ",\"selectionRange\":" + serialize_range(symbol.selection_range) + "}"
}

func serialize_completion_list(list completion_list) string {
    var result = "{\"isIncomplete\":" + (if list.is_incomplete { "true" } else { "false" })
    result = result + ",\"items\":["
    var i = 0
    for i < list.items.len() {
        if i > 0 {
            result = result + ","
        }
        result = result + serialize_completion_item(list.items[i])
        i = i + 1
    }
    result = result + "]}"
    result
}

func serialize_completion_item(item completion_item) string {
    var result = "{\"label\":\"" + escape_json_string(item.label) + "\""

    switch item.kind {
        option::some(k) : result = result + ",\"kind\":" + std::to_string(completion_kind_to_int(k)),
        option::none() : {}
    }

    switch item.detail {
        option::some(d) : result = result + ",\"detail\":\"" + escape_json_string(d) + "\"",
        option::none() : {}
    }

    switch item.documentation {
        option::some(doc) : result = result + ",\"documentation\":\"" + escape_json_string(doc) + "\"",
        option::none() : {}
    }

    switch item.sort_text {
        option::some(st) : result = result + ",\"sortText\":\"" + escape_json_string(st) + "\"",
        option::none() : {}
    }

    result = result + "}"
    result
}

func serialize_hover(h hover) string {
    "{\"contents\":\"" + escape_json_string(h.contents) + "\"}"
}

func serialize_range(r range) string {
    "{\"start\":" + serialize_position(r.start) + ",\"end\":" + serialize_position(r.end) + "}"
}

func serialize_position(p position) string {
    "{\"line\":" + std::to_string(p.line) + ",\"character\":" + std::to_string(p.character) + "}"
}

func serialize_severity(severity option[int]) string {
    switch severity {
        option::some(s) : std::to_string(s),
        option::none() : "4"
    }
}

func extract_json_string(json string, key string) option[string] {
    search_key := "\"" + key + "\":"
    switch std::find_substring(json, search_key) {
        option::some(pos) : {
            start := pos + search_key.len()

            for start < json.len() && (json[start] == " " || json[start] == "\t") {
                start = start + 1
            }

            if start < json.len() {
                if json[start] == "\"" {
                    end := start + 1
                    for end < json.len() && json[end] != "\"" {
                        if json[end] == "\\" {
                            end = end + 2
                        } else {
                            end = end + 1
                        }
                    }
                    if end < json.len() {
                        option::some(json.substring(start + 1, end))
                    } else {
                        option::none()
                    }
                } else {
                    end := start
                    for end < json.len() && json[end] != "," && json[end] != "}" && json[end] != "]" {
                        end = end + 1
                    }
                    option::some(json.substring(start, end))
                }
            } else {
                option::none()
            }
        },
        option::none() : option::none()
    }
}

func escape_json_string(s string) string {
    var result = ""
    var i = 0
    for i < s.len() {
        c := s[i]
        if c == "\"" {
            result = result + "\\\""
        } else if c == "\\" {
            result = result + "\\\\"
        } else if c == "\n" {
            result = result + "\\n"
        } else if c == "\r" {
            result = result + "\\r"
        } else if c == "\t" {
            result = result + "\\t"
        } else {
            result = result + c
        }
        i = i + 1
    }
    result
}

func symbol_kind_to_int(kind symbol_kind) int {
    switch kind {
        symbol_kind::file_k : 1,
        symbol_kind::module_k : 2,
        symbol_kind::namespace_k : 3,
        symbol_kind::package_k : 4,
        symbol_kind::class_k : 5,
        symbol_kind::method_k : 6,
        symbol_kind::property_k : 7,
        symbol_kind::field_k : 8,
        symbol_kind::constructor_k : 9,
        symbol_kind::enum_k : 10,
        symbol_kind::interface_k : 11,
        symbol_kind::function_k : 12,
        symbol_kind::variable_k : 13,
        symbol_kind::constant_k : 14,
        symbol_kind::string_k : 15,
        symbol_kind::number_k : 16,
        symbol_kind::boolean_k : 17,
        symbol_kind::array_k : 18,
        symbol_kind::object_k : 19,
        symbol_kind::key_k : 20,
        symbol_kind::null_k : 21,
        symbol_kind::enum_member_k : 22,
        symbol_kind::struct_k : 23,
        symbol_kind::event_k : 24,
        symbol_kind::operator_k : 25,
        symbol_kind::type_parameter_k : 26,
    }
}

func completion_kind_to_int(kind completion_item_kind) int {
    switch kind {
        completion_item_kind::text : 1,
        completion_item_kind::method : 2,
        completion_item_kind::function : 3,
        completion_item_kind::constructor : 4,
        completion_item_kind::field : 5,
        completion_item_kind::variable : 6,
        completion_item_kind::class : 7,
        completion_item_kind::interface : 8,
        completion_item_kind::module : 9,
        completion_item_kind::property : 10,
        completion_item_kind::unit : 11,
        completion_item_kind::value : 12,
        completion_item_kind::enum_value : 13,
        completion_item_kind::keyword : 14,
        completion_item_kind::snippet : 15,
        completion_item_kind::color : 16,
        completion_item_kind::file : 17,
        completion_item_kind::reference : 18,
        completion_item_kind::folder : 19,
        completion_item_kind::enum_member : 20,
        completion_item_kind::constant : 21,
        completion_item_kind::struct_k : 22,
        completion_item_kind::event : 23,
        completion_item_kind::operator : 24,
        completion_item_kind::type_parameter : 25,
    }
}
