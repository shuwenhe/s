package compile.internal.ownership

// Ownership State Machine
// Defines all possible states a variable can be in at any program point

// OwnershipState represents the state of a value
type OwnershipState int

const (
    // UNDEFINED - variable not yet initialized
    STATE_UNDEFINED OwnershipState = iota
    
    // OWNED - variable owns the resource, can be moved/dropped
    STATE_OWNED
    
    // MOVED - variable's ownership has been transferred (use-after-move ERROR)
    STATE_MOVED
    
    // BORROWED_SHARED - variable is borrowed for shared read access
    STATE_BORROWED_SHARED
    
    // BORROWED_MUT - variable is borrowed for mutable access
    STATE_BORROWED_MUT
    
    // PARTIALLY_MOVED - some fields of struct have been moved
    STATE_PARTIALLY_MOVED
    
    // DROPPED - variable has been dropped (use-after-drop ERROR)
    STATE_DROPPED
    
    // MAYBE_MOVED - control flow merge resulted in uncertain state
    STATE_MAYBE_MOVED
)

// String representation of ownership state
func (s OwnershipState) String() string {
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

type OwnershipInfo struct {
    State OwnershipState
    
    IsOwned bool
    IsCopy  bool
    
    ActiveBorrows   BorrowInfo[]
    
    FieldStates map[string]OwnershipState
}

type BorrowInfo tracks information about an active borrow
type BorrowInfo struct {
    // Borrow scope (lexical range where borrow is active)
    StartPC int
    EndPC   int
    
    // Type of borrow
    IsMutable bool
    
    // Source variable being borrowed
    Source string
    
    // The borrow's "lifetime" (inferred scope)
    LifetimeName string
}

type type_classification struct {
    NeedsOwnership bool
    IsCopy bool
    OwnedFields string[]
    DropOrder string[]
}

// OwnershipContext maintains ownership state across a function
type OwnershipContext struct {
    // Ownership state at each program point
    StateAtPC map[int]*OwnershipInfo
    
    // Type classifications for all types in scope
    TypeClasses map[string]*type_classification
    
    // Current control flow block
    CurrentBlock string
    
    BorrowStack []map[string]*BorrowInfo
    Errors string[]
}

// NewOwnershipContext creates a fresh ownership context
func NewOwnershipContext() *OwnershipContext {
    return &OwnershipContext{
        StateAtPC:   make(map[int]*OwnershipInfo),
        TypeClasses: make(map[string]*type_classification),
        BorrowStack: []map[string]*BorrowInfo{make(map[string]*BorrowInfo)},
        Errors:      make(string[], 0),
    }
}

// GetStateAt retrieves ownership state at a program point
func (ctx *OwnershipContext) GetStateAt(pc int, varName string) OwnershipState {
    info, ok := ctx.StateAtPC[pc]
    if !ok {
        return STATE_UNDEFINED
    }
    return info.State
}

// SetStateAt records ownership state at a program point
func (ctx *OwnershipContext) SetStateAt(pc int, varName string, state OwnershipState) {
    if _, ok := ctx.StateAtPC[pc]; !ok {
        ctx.StateAtPC[pc] = &OwnershipInfo{
            State:         state,
            ActiveBorrows: make(BorrowInfo[], 0),
            FieldStates:   make(map[string]OwnershipState),
        }
    } else {
        ctx.StateAtPC[pc].State = state
    }
}

// AddError records an ownership error
func (ctx *OwnershipContext) AddError(msg string) {
    ctx.Errors = append(ctx.Errors, msg)
}

// HasErrors checks if any errors were collected
func (ctx *OwnershipContext) HasErrors() bool {
    return len(ctx.Errors) > 0
}

func (ctx *OwnershipContext) classify_type(typeName string) *type_classification {
    if class, ok := ctx.TypeClasses[typeName]; ok {
        return class
    }
    
    // Default classification (can be overridden by semantic analysis)
    class := &type_classification{
        NeedsOwnership: !isPrimitiveType(typeName),
        IsCopy:         isPrimitiveType(typeName),
        OwnedFields:    make(string[], 0),
        DropOrder:      make(string[], 0),
    }
    
    ctx.TypeClasses[typeName] = class
    return class
}

// isPrimitiveType checks if a type is primitive (int, bool, etc)
func isPrimitiveType(typeName string) bool {
    switch typeName {
    case "int", "bool", "u8", "u16", "u32", "u64", "i8", "i16", "i32", "i64":
        return true
    default:
        return false
    }
}
