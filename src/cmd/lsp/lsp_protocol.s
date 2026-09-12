package lsp
struct position {
    line int
    character int
}

struct range {
    start position
    end position
}

struct location {
    uri string
    r range
}

struct diagnostic {
    r range
    message string
    option[int] severity
    option[string] code
    option[string] source
    option[diagnostic_related_information[]] related_information
}

struct diagnostic_related_information {
    location location
    message string
}

struct version_change_event {
    uri string
    text string
}

struct text_document {
    uri string
    language_id string
    version int
    text string
}

struct text_document_item {
    uri string
    language_id string
    version int
    text string
}

struct text_document_position_params {
    uri string
    pos position
}

struct text_document_identifier {
    uri string
}

struct versioned_text_document_identifier {
    uri string
    version int
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
    label string
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
    is_incomplete bool
    completion_item[] items
}

struct hover {
    contents string
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
    name string
    kind symbol_kind
    range_val range
    selection_range range
    option[document_symbol[]] children
    option[bool] deprecated
}

struct reference_params {
    uri string
    pos position
    option[bool] include_declaration
}

struct rename_params {
    uri string
    pos position
    new_name string
}

struct text_edit {
    r range
    new_text string
}

struct workspace_edit {
    map[string, text_edit[]] changes
}

struct server_capabilities {
    text_document_sync bool
    completion_provider bool
    hover_provider bool
    definition_provider bool
    references_provider bool
    document_symbol_provider bool
    rename_provider bool
    workspace_symbol_provider bool
}

struct initialize_result {
    capabilities server_capabilities
    option[string] server_info
}

struct text_document_content_change_event {
    option[range] range_val
    text string
}

struct did_change_text_document_params {
    text_document versioned_text_document_identifier
    text_document_content_change_event[] content_changes
}

struct did_open_text_document_params {
    text_document text_document_item
}

struct did_close_text_document_params {
    text_document text_document_identifier
}

struct did_save_text_document_params {
    text_document text_document_identifier
    option[string] text
}