package lsp

struct position {
    int line
    int character
}

struct range {
    position start
    position end
}

struct location {
    string uri
    range r
}

struct diagnostic {
    range r
    string message
    option[int] severity
    option[string] code
    option[string] source
    option[diagnostic_related_information[]] related_information
}

struct diagnostic_related_information {
    location location
    string message
}

struct version_change_event {
    string uri
    string text
}

struct text_document {
    string uri
    string language_id
    int version
    string text
}

struct text_document_item {
    string uri
    string language_id
    int version
    string text
}

struct text_document_position_params {
    string uri
    position pos
}

struct text_document_identifier {
    string uri
}

struct versioned_text_document_identifier {
    string uri
    int version
}

enum completion_item_kind {
    text,
    method,
    function,
    constructor,
    field,
    variable,
    class,
    interface,
    module,
    property,
    unit,
    value,
    enum_value,
    keyword,
    snippet,
    color,
    file,
    reference,
    folder,
    enum_member,
    constant,
    struct_k,
    event,
    operator,
    type_parameter,
}

struct completion_item {
    string label
    option[completion_item_kind] kind
    option[string] detail
    option[string] documentation
    option[string] sort_text
    option[string] filter_text
    option[string] text_edit_text
    option[bool] deprecated
    option[int] score
}

struct completion_list {
    bool is_incomplete
    completion_item[] items
}

struct hover {
    string contents
    option[range] r
}

enum symbol_kind {
    file_k,
    module_k,
    namespace_k,
    package_k,
    class_k,
    method_k,
    property_k,
    field_k,
    constructor_k,
    enum_k,
    interface_k,
    function_k,
    variable_k,
    constant_k,
    string_k,
    number_k,
    boolean_k,
    array_k,
    object_k,
    key_k,
    null_k,
    enum_member_k,
    struct_k,
    event_k,
    operator_k,
    type_parameter_k,
}

struct document_symbol {
    string name
    symbol_kind kind
    range range_val
    range selection_range
    option[document_symbol[]] children
    option[bool] deprecated
}

struct reference_params {
    string uri
    position pos
    option[bool] include_declaration
}

struct rename_params {
    string uri
    position pos
    string new_name
}

struct text_edit {
    range r
    string new_text
}

struct workspace_edit {
    map[string, text_edit[]] changes
}

struct server_capabilities {
    bool text_document_sync
    bool completion_provider
    bool hover_provider
    bool definition_provider
    bool references_provider
    bool document_symbol_provider
    bool rename_provider
    bool workspace_symbol_provider
}

struct initialize_result {
    server_capabilities capabilities
    option[string] server_info
}

struct text_document_content_change_event {
    option[range] range_val
    string text
}

struct did_change_text_document_params {
    versioned_text_document_identifier text_document
    text_document_content_change_event[] content_changes
}

struct did_open_text_document_params {
    text_document_item text_document
}

struct did_close_text_document_params {
    text_document_identifier text_document
}

struct did_save_text_document_params {
    text_document_identifier text_document
    option[string] text
}
