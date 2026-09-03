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
