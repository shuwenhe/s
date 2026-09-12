package compile.internal.field_virtualization

use compile.internal.path.path
use compile.internal.path.path_new
use compile.internal.path.path_field
use compile.internal.field_level_drop_flag.field_level_drop_flag
use compile.internal.field_level_drop_flag.fldf_new
use compile.internal.field_level_drop_flag.fldf_declare
use compile.internal.field_level_drop_flag.fldf_move
use compile.internal.field_level_drop_flag.fldf_use

func field_encode_virtual_name(string base_var, string field_name) string {
    "__field_" + base_var + "_" + field_name
}

func field_decode_virtual_name(string virt_name) (string, string) {
    if string(virt_name[0]) != "_" || len(virt_name) < 8 {
        return ("", "")
    }

    i := 8
    base_end := -1

    j := len(virt_name) - 1
    for j > i {
        if string(virt_name[j]) == "_" {
            base_end = j
            break
        }
        j = j - 1
    }

    if base_end <= i {
        return ("", "")
    }

    base := slice(virt_name, i, base_end)
    field := slice(virt_name, base_end + 1, len(virt_name))
    (base, field)
}

struct field_access_record {
    string virtual_name
    string base_var
    string field_name
    field_path path
    int line
    int column
}

struct field_virtualization_context {
    field_access_record[] records
    drop_flag field_level_drop_flag
    int error_count
    string[] error_messages
}

func field_virt_new() field_virtualization_context {
    field_virtualization_context {
        records: make(field_access_record[], 0),
        drop_flag: fldf_new(),
        error_count: 0,
        error_messages: make(string[], 0)
    }
}

func field_virt_declare_field(field_virtualization_context ctx, string base_var, string field_name, string field_type, int line, int col) field_virtualization_context {
    virt_name := field_encode_virtual_name(base_var, field_name)
    p := path_new(base_var)
    p = path_field(p, field_name)

    ctx.drop_flag = fldf_declare(ctx.drop_flag, p, field_type)

    record := field_access_record {
        virtual_name: virt_name,
        base_var: base_var,
        field_name: field_name,
        field_path: p,
        line: line,
        column: col
    }

    ctx.records = append(ctx.records, record)
    ctx
}

func field_virt_move(field_virtualization_context ctx, string from_base, string from_field, string to_var, int line, int col) field_virtualization_context {
    from_path := path_new(from_base)
    from_path = path_field(from_path, from_field)

    to_path := path_new(to_var)

    ctx.drop_flag = fldf_move(ctx.drop_flag, from_path, to_path, line, col)
    ctx
}

func field_virt_use(field_virtualization_context ctx, string base_var, string field_name, int line, int col) field_virtualization_context {
    p := path_new(base_var)
    p = path_field(p, field_name)

    ctx.drop_flag = fldf_use(ctx.drop_flag, p)
    ctx
}

func field_virt_has_errors(field_virtualization_context ctx) bool {
    ctx.error_count > 0
}

func field_virt_get_error_count(field_virtualization_context ctx) int {
    ctx.error_count
}