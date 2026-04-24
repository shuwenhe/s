package compile.internal.ssa

func op_invalid() string { "Invalid" }
func op_const() string { "Const" }
func op_copy() string { "Copy" }
func op_add() string { "Add" }
func op_sub() string { "Sub" }
func op_mul() string { "Mul" }
func op_div() string { "Div" }
func op_phi() string { "Phi" }
func op_call() string { "Call" }
func op_store() string { "Store" }
func op_load() string { "Load" }
func op_return() string { "Return" }
func op_branch() string { "Branch" }

func op_has_side_effect(string op) bool {
    op == op_call() || op == op_store() || op == op_return() || op == op_branch()
}

func op_is_pure(string op) bool {
    !(op_has_side_effect(op))
}
