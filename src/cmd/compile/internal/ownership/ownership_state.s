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
type ownership_info struct {
    State OwnershipState
    IsOwned bool
    IsCopy  bool
    ActiveBorrows   borrow_info[]
    FieldStates map[string]OwnershipState
}
type borrow_info tracks information about an active borrow
type borrow_info struct {
    StartPC int
    EndPC   int
    IsMutable bool
    Source string
    LifetimeName string
}
type type_classification struct {
    NeedsOwnership bool
    IsCopy bool
    OwnedFields string[]
    DropOrder string[]
}
type ownership_context struct {
    StateAtPC map[int]*OwnershipInfo
    TypeClasses map[string]*type_classification
    CurrentBlock string
    BorrowStack []map[string]*borrow_info
    Errors string[]
}

func new_ownership_context() OwnershipContext* {
    return OwnershipContext*{
        StateAtPC:   make(map[int]*OwnershipInfo),
        TypeClasses: make(map[string]*type_classification),
        BorrowStack: []map[string]*borrow_info{make(map[string]*borrow_info)},
        Errors:      make(string[], 0),
    }
}

func (OwnershipContext* ctx) get_state_at(int pc, string varName) OwnershipState {
    info, ok := ctx.StateAtPC[pc]
    if !ok {
        return STATE_UNDEFINED
    }
    return info.State
}

func (OwnershipContext* ctx) set_state_at(int pc, string varName, state OwnershipState) {
    if _, ok := ctx.StateAtPC[pc]; !ok {
        ctx.StateAtPC[pc] = OwnershipInfo*{
            State:         state,
            ActiveBorrows: make(borrow_info[], 0),
            FieldStates:   make(map[string]OwnershipState),
        }
    } else {
        ctx.StateAtPC[pc].State = state
    }
}

func (OwnershipContext* ctx) add_error(string msg) {
    ctx.Errors = append(ctx.Errors, msg)
}

func (OwnershipContext* ctx) has_errors() bool {
    return len(ctx.Errors) > 0
}

func (OwnershipContext* ctx) classify_type(string typeName) type_classification* {
    if class, ok := ctx.TypeClasses[typeName]; ok {
        return class
    }
    class := type_classification*{
        NeedsOwnership: !isPrimitiveType(typeName),
        IsCopy:         isPrimitiveType(typeName),
        OwnedFields:    make(string[], 0),
        DropOrder:      make(string[], 0),
    }
    ctx.TypeClasses[typeName] = class
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
