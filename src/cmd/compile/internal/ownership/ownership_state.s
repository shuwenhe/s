package compile.internal.ownership
type OwnershipState int
const (
    STATE_UNDEFINED OwnershipState = iota
    STATE_OWNED
    STATE_MOVED
    STATE_BORROWED_SHARED
    STATE_BORROWED_MUT
    STATE_PARTIALLY_MOVED
    STATE_DROPPED
    STATE_MAYBE_MOVED
)

func (s OwnershipState) string() string {
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
    state OwnershipState
    is_owned bool
    is_copy  bool
    active_borrows   borrow_info[]
    field_states map[string]OwnershipState
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

func new_ownership_context() OwnershipContext* {
    return OwnershipContext*{
        state_at_pc:   make(map[int]*ownership_info),
        type_classes: make(map[string]*type_classification),
        borrow_stack: []map[string]*borrow_info{make(map[string]*borrow_info)},
        errors:      make(string[], 0),
    }
}

func (OwnershipContext* ctx) get_state_at(int pc, string varName) OwnershipState {
    info, ok := ctx.state_at_pc[pc]
    if !ok {
        return STATE_UNDEFINED
    }
    return info.state
}

func (OwnershipContext* ctx) set_state_at(int pc, string varName, state OwnershipState) {
    if _, ok := ctx.state_at_pc[pc]; !ok {
        ctx.state_at_pc[pc] = ownership_info*{
            state:         state,
            active_borrows: make(borrow_info[], 0),
            field_states:   make(map[string]OwnershipState),
        }
    } else {
        ctx.state_at_pc[pc].state = state
    }
}

func (OwnershipContext* ctx) add_error(string msg) {
    ctx.errors = append(ctx.errors, msg)
}

func (OwnershipContext* ctx) has_errors() bool {
    return len(ctx.errors) > 0
}

func (OwnershipContext* ctx) classify_type(string typeName) type_classification* {
    if class, ok := ctx.type_classes[typeName]; ok {
        return class
    }
    class := type_classification*{
        NeedsOwnership: !isPrimitiveType(typeName),
        is_copy:         isPrimitiveType(typeName),
        OwnedFields:    make(string[], 0),
        drop_order:      make(string[], 0),
    }
    ctx.type_classes[typeName] = class
    return class
}

func is_primitive_type(string typeName) bool {
    switch typeName {
    case "int", "bool", "u8", "u16", "u32", "u64", "i8", "i16", "i32", "i64":
        return true
    default:
        return false
    }
}
