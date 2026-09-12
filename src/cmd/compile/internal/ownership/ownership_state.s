package compile.internal.ownership
type ownership_state int
const (
    STATE_UNDEFINED ownership_state = iota
    STATE_OWNED
    STATE_MOVED
    STATE_BORROWED_SHARED
    STATE_BORROWED_MUT
    STATE_PARTIALLY_MOVED
    STATE_DROPPED
    STATE_MAYBE_MOVED
)

func (s ownership_state) string() string {
    switch s {
    case STATE_UNDEFINED:
        return "UNDEFINED"
    case STATE_OWNED:
        return "OWNED"
    case STATE_MOVED:
        return "MOVED"
    case STATE_BORROWED_SHARED:
        return "BORROWED_SHARED"
    case STATE_BORROWED_MUT:
        return "BORROWED_MUT"
    case STATE_PARTIALLY_MOVED:
        return "PARTIALLY_MOVED"
    case STATE_DROPPED:
        return "DROPPED"
    case STATE_MAYBE_MOVED:
        return "MAYBE_MOVED"
    default:
        return "UNKNOWN"
    }
}

struct ownership_info {
    state ownership_state
    is_owned bool
    is_copy  bool
    active_borrows   borrow_info[]
    field_states map[string]ownership_state
}
type borrow_info tracks information about an active borrow
struct borrow_info {
    start_pc int
    end_pc   int
    is_mutable bool
    source    string
    lifetime_name string
}

struct type_classification {
    needs_ownership bool
    is_copy bool
    owned_fields string[]
    drop_order string[]
}

struct ownership_context {
    state_at_pc map[int]*ownership_info
    type_classes map[string]*type_classification
    current_block string
    borrow_stack []map[string]*borrow_info
    errors string[]
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
        return STATE_UNDEFINED
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
        NeedsOwnership: !isPrimitiveType(type_name),
        is_copy:         isPrimitiveType(type_name),
        OwnedFields:    make(string[], 0),
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
