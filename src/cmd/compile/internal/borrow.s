package compile.internal.borrow
use s.function_decl
use s.block_expr
use s.expr
use s.stmt
func analyze_block() int {
    return 0
}

func analyze_trace(string scope, string[] type_env, string block_text) string {
    plan := make_plan_trace(type_env)
    text := "borrow " + scope
    if block_text != "" {
        text = text + " | " + block_text
    }
    if len(plan) == 0 {
        return text + " | plan <empty>"
    }
    return text + " | plan " + join_text(plan, ", ")
}

func analyze_function(string name, string[] type_env, string body_text) string {
    return analyze_trace(name, type_env, body_text)
}

func analyze_expr(string scope, string expr_text) string {
    if expr_text == "" {
        return "expr " + scope + " | <empty>"
    }
    return "expr " + scope + " | " + expr_text
}

func join_text(string[] values, string sep) string {
    out := ""
    i := 0
    for i < len(values) {
        if i > 0 {
            out = out + sep
        }
        out = out + values[i]
        i = i + 1
    }
    return out
}

func make_plan_trace(string[] type_env) string[] {
    plan := string[] {}
    i := 0
    for i < len(type_env) {
        ty := type_env[i]
        if ty == "" {
            plan = append(plan, "borrow:<empty>")
        } else if starts_with(ty, "&") {
            plan = append(plan, "copy:" + ty)
        } else {
            plan = append(plan, "drop:" + ty)
        }
        i = i + 1
    }
    return plan
}

func starts_with(string text, string prefix) bool {
    prefix_len := len(prefix)
    if prefix_len > len(text) {
        return false
    }
    return slice(text, 0, prefix_len) == prefix
}

struct borrow_slot {
    string name
    int shared_count
    bool mutable_borrowed
    bool moved
}

struct borrow_check_result {
    bool ok
    int errors
    string message
}

func borrow_find_slot(borrow_slot[] slots, string name) int {
    i := 0
    for i < len(slots) {
        if slots[i].name == name { return i }
        i = i + 1
    }
    -1
}

func borrow_check_events(string[] events) borrow_check_result {
    slots := borrow_slot[] {}
    errors := 0
    message := ""
    i := 0
    for i < len(events) {
        event := events[i]
        colon := find_event_colon(event)
        if colon <= 0 {
            errors = errors + 1
            message = message + "invalid event;"
            i = i + 1
            continue
        }
        kind := slice(event, 0, colon)
        name := slice(event, colon + 1, len(event))
        slot_id := borrow_find_slot(slots, name)
        if slot_id < 0 {
            slots = append(slots, borrow_slot { name: name, shared_count: 0, mutable_borrowed: false, moved: false })
            slot_id = len(slots) - 1
        }
        slot := slots[slot_id]
        if kind == "move" {
            if slot.moved || slot.shared_count > 0 || slot.mutable_borrowed {
                errors = errors + 1
                message = message + "move-conflict:" + name + ";"
            } else {
                slot.moved = true
            }
        } else if kind == "read" {
            if slot.moved || slot.mutable_borrowed {
                errors = errors + 1
                message = message + "read-conflict:" + name + ";"
            }
        } else if kind == "write" {
            if slot.moved || slot.mutable_borrowed || slot.shared_count > 0 {
                errors = errors + 1
                message = message + "write-conflict:" + name + ";"
            }
        } else if kind == "shared" {
            if slot.moved || slot.mutable_borrowed {
                errors = errors + 1
                message = message + "shared-conflict:" + name + ";"
            } else {
                slot.shared_count = slot.shared_count + 1
            }
        } else if kind == "mutable" {
            if slot.moved || slot.mutable_borrowed || slot.shared_count > 0 {
                errors = errors + 1
                message = message + "mutable-conflict:" + name + ";"
            } else {
                slot.mutable_borrowed = true
            }
        } else if kind == "end_shared" {
            if slot.shared_count > 0 { slot.shared_count = slot.shared_count - 1 }
        } else if kind == "end_mutable" {
            slot.mutable_borrowed = false
        } else {
            errors = errors + 1
            message = message + "unknown-event:" + kind + ";"
        }
        i = i + 1
    }
    borrow_check_result { ok: errors == 0, errors: errors, message: message }
}

func find_event_colon(string event) int {
    i := 0
    for i < len(event) {
        if string(event[i]) == ":" { return i }
        i = i + 1
    }
    -1
}

func borrow_check_function(function_decl function) int {
    if function.body.is_none() { return 0 }
    borrow_check_block(function.body.unwrap(), borrow_slot[] {})
}

func borrow_check_block(block_expr block, borrow_slot[] slots) int {
    errors := 0
    i := 0
    for i < len(block.statements) {
        switch block.statements[i] {
            stmt.let(value) : {
                errors = errors + borrow_check_expr(value.value, slots, false)
                if is_direct_borrow(value.value) {
                    target := borrow_target_name(value.value)
                    slot_id := borrow_find_slot(slots, target)
                    if slot_id < 0 {
                        slots = append(slots, borrow_slot { name: target, shared_count: 0, mutable_borrowed: false, moved: false })
                        slot_id = len(slots) - 1
                    }
                    slot := slots[slot_id]
                    if is_mutable_borrow(value.value) {
                        if slot.shared_count > 0 || slot.mutable_borrowed || slot.moved { errors = errors + 1 }
                        slot.mutable_borrowed = true
                    } else {
                        if slot.mutable_borrowed || slot.moved { errors = errors + 1 }
                        slot.shared_count = slot.shared_count + 1
                    }
                }
            }
            stmt.assign(value) : {
                slot_id := borrow_find_slot(slots, value.name)
                if slot_id >= 0 && (slots[slot_id].shared_count > 0 || slots[slot_id].mutable_borrowed) { errors = errors + 1 }
                errors = errors + borrow_check_expr(value.value, slots, false)
            }
            stmt.return(value) : {
                switch value.value {
                    option.some(return_expr) : errors = errors + borrow_check_expr(return_expr, slots, true),
                    option.none : (),
                }
            }
            stmt.c_for(value) : errors = errors + borrow_check_block(value.body, slots),
            _ : (),
        }
        i = i + 1
    }
    errors
}

func borrow_check_expr(expr value, borrow_slot[] slots, bool escaping) int {
    switch value {
        expr::name(name_value) : {
            slot_id := borrow_find_slot(slots, name_value.name)
            if slot_id >= 0 && (slots[slot_id].moved || (escaping && slots[slot_id].mutable_borrowed)) { return 1 }
            0
        }
        expr::borrow(borrow_value) : {
            if escaping { return 1 }
            0
        }
        expr::binary(binary_value) : borrow_check_expr(binary_value.left.value, slots, false) + borrow_check_expr(binary_value.right.value, slots, false),
        expr::member(member_value) : borrow_check_expr(member_value.target.value, slots, false),
        expr::index(index_value) : borrow_check_expr(index_value.target.value, slots, false) + borrow_check_expr(index_value.index.value, slots, false),
        expr::call(call_value) : borrow_check_call_args(call_value.args, slots),
        _ : 0,
    }
}

func borrow_check_call_args(expr[] args, borrow_slot[] slots) int {
    errors := 0
    i := 0
    for i < len(args) {
        errors = errors + borrow_check_expr(args[i], slots, false)
        i = i + 1
    }
    errors
}

func is_direct_borrow(expr value) bool {
    switch value {
        expr::borrow(_) : true,
        _ : false,
    }
}

func is_mutable_borrow(expr value) bool {
    switch value {
        expr::borrow(borrow_value) : borrow_value.mutable,
        _ : false,
    }
}

func borrow_target_name(expr value) string {
    switch value {
        expr::borrow(borrow_value) : {
            switch borrow_value.target.value {
                expr::name(name_value) : name_value.name,
                _ : "<temporary>",
            }
        }
        _ : "<unknown>",
    }
}
