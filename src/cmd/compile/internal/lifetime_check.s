package compile.internal.lifetime_check

struct lifetime_scope {
    name string
    active bool
}

struct lifetime_borrow {
    ref_name string
    owner_scope string
    ref_scope string
    mutable bool
    active bool
}

struct lifetime_context {
    lifetime_scope[] scopes
    lifetime_borrow[] borrows
    string[] errors
}

struct lifetime_result {
    ok bool
    message string
}

struct dropck_field {
    name string
    lifetime_name string
    accessed_by_drop bool
}

func lifetime_context_new() lifetime_context {
    lifetime_scope[] scopes
    lifetime_borrow[] borrows
    string[] errors
    lifetime_context { scopes: scopes, borrows: borrows, errors: errors }
}

func lifetime_error(lifetime_context ctx, string message) lifetime_context {
    ctx.errors = append(ctx.errors, message)
    ctx
}

func lifetime_scope_find(lifetime_context ctx, string name) int {
    i := len(ctx.scopes) - 1
    for i >= 0 {
        if ctx.scopes[i].name == name { return i }
        i = i - 1
    }
    -1
}

func lifetime_enter_scope(lifetime_context ctx, string name) lifetime_context {
    if lifetime_scope_find(ctx, name) >= 0 {
        return lifetime_error(ctx, "duplicate scope: " + name)
    }
    ctx.scopes = append(ctx.scopes, lifetime_scope { name: name, active: true })
    ctx
}

func lifetime_end_scope(lifetime_context ctx, string name) lifetime_context {
    index := lifetime_scope_find(ctx, name)
    if index < 0 || !ctx.scopes[index].active {
        return lifetime_error(ctx, "unknown or inactive scope: " + name)
    }
    ctx.scopes[index].active = false
    i := 0
    for i < len(ctx.borrows) {
        b := ctx.borrows[i]
        if b.active && (b.owner_scope == name || b.ref_scope == name) {
            ctx.borrows[i].active = false
        }
        i = i + 1
    }
    ctx
}

func lifetime_scope_active(lifetime_context ctx, string name) bool {
    index := lifetime_scope_find(ctx, name)
    index >= 0 && ctx.scopes[index].active
}

func lifetime_scope_order(lifetime_context ctx, string name) int {
    i := 0
    for i < len(ctx.scopes) {
        if ctx.scopes[i].name == name { return i }
        i = i + 1
    }
    -1
}

func lifetime_borrow_find(lifetime_context ctx, string ref_name) int {
    i := 0
    for i < len(ctx.borrows) {
        if ctx.borrows[i].ref_name == ref_name { return i }
        i = i + 1
    }
    -1
}

func lifetime_create_borrow(lifetime_context ctx, string ref_name, string owner_scope, string ref_scope, bool mutable) lifetime_context {
    if lifetime_borrow_find(ctx, ref_name) >= 0 {
        return lifetime_error(ctx, "duplicate reference: " + ref_name)
    }
    owner_index := lifetime_scope_order(ctx, owner_scope)
    ref_index := lifetime_scope_order(ctx, ref_scope)
    if owner_index < 0 || ref_index < 0 || !lifetime_scope_active(ctx, owner_scope) || !lifetime_scope_active(ctx, ref_scope) {
        return lifetime_error(ctx, "borrow from inactive scope: " + ref_name)
    }
    if owner_index > ref_index {
        return lifetime_error(ctx, "borrow would outlive owner: " + ref_name)
    }
    ctx.borrows = append(ctx.borrows, lifetime_borrow {
        ref_name: ref_name, owner_scope: owner_scope, ref_scope: ref_scope, mutable: mutable, active: true,
    })
    ctx
}

func lifetime_use_ref(lifetime_context ctx, string ref_name) lifetime_context {
    index := lifetime_borrow_find(ctx, ref_name)
    if index < 0 || !ctx.borrows[index].active {
        return lifetime_error(ctx, "use of inactive reference: " + ref_name)
    }
    b := ctx.borrows[index]
    if !lifetime_scope_active(ctx, b.owner_scope) || !lifetime_scope_active(ctx, b.ref_scope) {
        return lifetime_error(ctx, "dangling reference: " + ref_name)
    }
    ctx
}

func lifetime_end_borrow(lifetime_context ctx, string ref_name) lifetime_context {
    index := lifetime_borrow_find(ctx, ref_name)
    if index < 0 || !ctx.borrows[index].active {
        return lifetime_error(ctx, "end of inactive borrow: " + ref_name)
    }
    ctx.borrows[index].active = false
    ctx
}

func lifetime_finish(lifetime_context ctx) lifetime_result {
    message := ""
    i := 0
    for i < len(ctx.errors) {
        message = message + ctx.errors[i] + ";"
        i = i + 1
    }
    lifetime_result { ok: len(ctx.errors) == 0, message: message }
}

func dropck_check_fields(string type_name, dropck_field[] fields) lifetime_result {
    string[] errors
    i := 0
    for i < len(fields) {
        field := fields[i]
        if field.accessed_by_drop && field.lifetime_name == "" {
            errors = append(errors, "Drop for " + type_name + " accesses field without lifetime: " + field.name)
        }
        i = i + 1
    }
    message := ""
    j := 0
    for j < len(errors) {
        message = message + errors[j] + ";"
        j = j + 1
    }
    lifetime_result { ok: len(errors) == 0, message: message }
}