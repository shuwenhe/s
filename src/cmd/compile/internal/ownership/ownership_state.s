package compile.internal.ownership
type ownership_state int
const (
    state_undefined ownership_state = iota
    state_owned
    state_moved
    state_borrowed_shared
    state_borrowed_mut
    state_partially_moved
    state_dropped
    state_maybe_moved
)

func (s ownership_state) string() string {
    switch s {
    case state_undefined:
        return "undefined"
    case state_owned:
        return "owned"
    case state_moved:
        return "moved"
    case state_borrowed_shared:
        return "borrowed_shared"
    case state_borrowed_mut:
        return "borrowed_mut"
    case state_partially_moved:
        return "partially_moved"
    case state_dropped:
        return "dropped"
    case state_maybe_moved:
        return "maybe_moved"
    default:
        return "unknown"
    }
}

struct ownership_info {
    ownership_state state
    bool is_owned
    bool is_copy
    borrow_info[] active_borrows
    map[string]ownership_state field_states
}
type borrow_info tracks information about an active borrow
struct borrow_info {
    int start_pc
    int end_pc
    bool is_mutable
    string source
    string lifetime_name
}

struct type_classification {
    bool needs_ownership
    bool is_copy
    string[] owned_fields
    string[] drop_order
}

struct ownership_context {
    map[int]*ownership_info state_at_pc
    map[string]*type_classification type_classes
    string current_block
    []map[string]*borrow_info borrow_stack
    string[] errors
}

func new_ownership_context() ownership_context* {
    return ownership_context*{
        state_at_pc:   make(map[int]*ownership_info),
        type_classes: make(map[string]*type_classification),
        borrow_stack: []map[string]*borrow_info{make(map[string]*borrow_info)},
        errors:      make(string[], 0),
    }
}

func (ownership_context* ctx) get_state_at(int pc, string var_name) ownership_state {
    info, ok := ctx.state_at_pc[pc]
    if !ok {
        return state_undefined
    }
    return info.state
}

func (ownership_context* ctx) set_state_at(int pc, string var_name, state ownership_state) {
    if _, ok := ctx.state_at_pc[pc]; !ok {
        ctx.state_at_pc[pc] = ownership_info*{
            state:         state,
            active_borrows: make(borrow_info[], 0),
            field_states:   make(map[string]ownership_state),
        }
    } else {
        ctx.state_at_pc[pc].state = state
    }
}

func (ownership_context* ctx) add_error(string msg) {
    ctx.errors = append(ctx.errors, msg)
}

func (ownership_context* ctx) has_errors() bool {
    return len(ctx.errors) > 0
}

func (ownership_context* ctx) classify_type(string type_name) type_classification* {
    if class, ok := ctx.type_classes[type_name]; ok {
        return class
    }
    class := type_classification*{
        needs_ownership: !isPrimitiveType(type_name),
        is_copy:         isPrimitiveType(type_name),
        owned_fields:    make(string[], 0),
        drop_order:      make(string[], 0),
    }
    ctx.type_classes[type_name] = class
    return class
}

func is_primitive_type(string type_name) bool {
    switch type_name {
    case "int", "bool", "u8", "u16", "u32", "u64", "i8", "i16", "i32", "i64":
        return true
    default:
        return false
    }
}
