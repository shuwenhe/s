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
    string[] plan
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

// Ownership events are the small contract consumed by the future MIR pass.
// The checker deliberately operates on named places first; field- and
// projection-sensitive places can be added without changing the state model.
struct ownership_slot {
    string name
    bool copyable
    bool moved
    bool dropped
}

struct ownership_check_result {
    bool ok
    int errors
    string message
}

func ownership_find_slot(ownership_slot[] slots, string name) int {
    i := 0
    for i < len(slots) {
        if slots[i].name == name { return i }
        i = i + 1
    }
    -1
}

func ownership_event_payload(string event, int first) string {
    slice(event, first + 1, len(event))
}

func ownership_next_colon(string text, int start) int {
    i := start
    for i < len(text) {
        if string(text[i]) == ":" { return i }
        i = i + 1
    }
    -1
}

// Check ownership events emitted by MIR lowering.
// Supported events:
//   declare:name:copy, declare:name:move, use:name, move:name,
//   copy:name, drop:name
func ownership_check_events(string[] events) ownership_check_result {
    ownership_slot[] slots
    errors := 0
    message := ""
    i := 0
    for i < len(events) {
        event := events[i]
        first := find_event_colon(event)
        if first <= 0 {
            errors = errors + 1
            message = message + "invalid-ownership-event;"
            i = i + 1
            continue
        }
        kind := slice(event, 0, first)
        payload := ownership_event_payload(event, first)

        if kind == "declare" {
            second := ownership_next_colon(payload, 0)
            if second <= 0 {
                errors = errors + 1
                message = message + "invalid-declaration;"
                i = i + 1
                continue
            }
            name := slice(payload, 0, second)
            mode := slice(payload, second + 1, len(payload))
            if ownership_find_slot(slots, name) >= 0 {
                errors = errors + 1
                message = message + "duplicate-declaration:" + name + ";"
            } else if mode != "copy" && mode != "move" {
                errors = errors + 1
                message = message + "unknown-ownership-mode:" + mode + ";"
            } else {
                slots = append(slots, ownership_slot {
                    name: name, copyable: mode == "copy", moved: false, dropped: false,
                })
            }
            i = i + 1
            continue
        }

        slot_id := ownership_find_slot(slots, payload)
        if slot_id < 0 {
            errors = errors + 1
            message = message + "unknown-place:" + payload + ";"
            i = i + 1
            continue
        }
        slot := slots[slot_id]
        if kind == "use" {
            if slot.moved || slot.dropped {
                errors = errors + 1
                message = message + "use-after-move-or-drop:" + payload + ";"
            }
        } else if kind == "move" {
            if slot.moved || slot.dropped {
                errors = errors + 1
                message = message + "move-after-move-or-drop:" + payload + ";"
            } else {
                slot.moved = true
            }
        } else if kind == "copy" {
            if !slot.copyable {
                errors = errors + 1
                message = message + "copy-of-noncopy:" + payload + ";"
            } else if slot.moved || slot.dropped {
                errors = errors + 1
                message = message + "copy-after-move-or-drop:" + payload + ";"
            }
        } else if kind == "drop" {
            if slot.dropped {
                errors = errors + 1
                message = message + "double-drop:" + payload + ";"
            } else {
                slot.dropped = true
            }
        } else {
            errors = errors + 1
            message = message + "unknown-ownership-event:" + kind + ";"
        }
        i = i + 1
    }
    ownership_check_result { ok: errors == 0, errors: errors, message: message }
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
    borrow_slot[] slots
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
        if kind == "declare" {
            if slot_id >= 0 {
                errors = errors + 1
                message = message + "duplicate-declaration:" + name + ";"
            } else {
                slots = append(slots, borrow_slot { name: name, shared_count: 0, mutable_borrowed: false, moved: false })
            }
            i = i + 1
            continue
        }
        if slot_id < 0 {
            errors = errors + 1
            message = message + "unknown-place:" + name + ";"
            i = i + 1
            continue
        }
        if kind == "move" {
            if slots[slot_id].moved || slots[slot_id].shared_count > 0 || slots[slot_id].mutable_borrowed {
                errors = errors + 1
                message = message + "move-conflict:" + name + ";"
            } else {
                slots[slot_id].moved = true
            }
        } else if kind == "read" {
            if slots[slot_id].moved || slots[slot_id].mutable_borrowed {
                errors = errors + 1
                message = message + "read-conflict:" + name + ";"
            }
        } else if kind == "write" {
            if slots[slot_id].moved || slots[slot_id].mutable_borrowed || slots[slot_id].shared_count > 0 {
                errors = errors + 1
                message = message + "write-conflict:" + name + ";"
            }
        } else if kind == "shared" {
            if slots[slot_id].moved || slots[slot_id].mutable_borrowed {
                errors = errors + 1
                message = message + "shared-conflict:" + name + ";"
            } else {
                slots[slot_id].shared_count = slots[slot_id].shared_count + 1
            }
        } else if kind == "mutable" {
            if slots[slot_id].moved || slots[slot_id].mutable_borrowed || slots[slot_id].shared_count > 0 {
                errors = errors + 1
                message = message + "mutable-conflict:" + name + ";"
            } else {
                slots[slot_id].mutable_borrowed = true
            }
        } else if kind == "end_shared" {
            if slots[slot_id].shared_count > 0 {
                slots[slot_id].shared_count = slots[slot_id].shared_count - 1
            } else {
                errors = errors + 1
                message = message + "end-of-inactive-shared-borrow:" + name + ";"
            }
        } else if kind == "end_mutable" {
            if slots[slot_id].mutable_borrowed {
                slots[slot_id].mutable_borrowed = false
            } else {
                errors = errors + 1
                message = message + "end-of-inactive-mutable-borrow:" + name + ";"
            }
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

struct lifetime_reference {
    string reference_name
    string owner_name
    string scope_name
}

struct lifetime_check_result {
    bool ok
    int errors
    string message
}

func lifetime_find_reference(lifetime_reference[] refs, string name) int {
    i := 0
    for i < len(refs) {
        if refs[i].reference_name == name { return i }
        i = i + 1
    }
    -1
}

func lifetime_contains(string[] names, string name) bool {
    i := 0
    for i < len(names) {
        if names[i] == name { return true }
        i = i + 1
    }
    false
}

func lifetime_second_colon(string text, int first) int {
    i := first + 1
    for i < len(text) {
        if string(text[i]) == ":" { return i }
        i = i + 1
    }
    -1
}

func lifetime_check_events(string[] events) lifetime_check_result {
    lifetime_reference[] refs
    string[] active_scopes
    string[] ended_scopes
    string[] ended_refs
    errors := 0
    message := ""
    i := 0
    for i < len(events) {
        event := events[i]
        first := find_event_colon(event)
        if first <= 0 {
            errors = errors + 1
            message = message + "invalid-lifetime-event;"
            i = i + 1
            continue
        }
        kind := slice(event, 0, first)
        payload := slice(event, first + 1, len(event))
        if kind == "scope" {
            if lifetime_contains(active_scopes, payload) || lifetime_contains(ended_scopes, payload) {
                errors = errors + 1
                message = message + "duplicate-scope:" + payload + ";"
            } else {
                active_scopes = append(active_scopes, payload)
            }
        } else if kind == "end_scope" {
            if !lifetime_contains(active_scopes, payload) {
                errors = errors + 1
                message = message + "unknown-scope:" + payload + ";"
            } else {
                ended_scopes = append(ended_scopes, payload)
            }
        } else if kind == "borrow" {
            second := lifetime_second_colon(payload, 0)
            if second <= 0 {
                errors = errors + 1
                message = message + "invalid-borrow-lifetime;"
            } else {
                ref_name := slice(payload, 0, second)
                rest := slice(payload, second + 1, len(payload))
                third := lifetime_second_colon(rest, 0)
                if third <= 0 {
                    errors = errors + 1
                    message = message + "invalid-borrow-lifetime;"
                } else {
                    owner := slice(rest, 0, third)
                    scope := slice(rest, third + 1, len(rest))
                    if lifetime_find_reference(refs, ref_name) >= 0 || !lifetime_contains(active_scopes, owner) || !lifetime_contains(active_scopes, scope) {
                        errors = errors + 1
                        message = message + "borrow-lifetime-conflict:" + ref_name + ";"
                    } else {
                        refs = append(refs, lifetime_reference { reference_name: ref_name, owner_name: owner, scope_name: scope })
                    }
                }
            }
        } else if kind == "use_ref" || kind == "end_borrow" {
            ref_id := lifetime_find_reference(refs, payload)
            if ref_id < 0 || lifetime_contains(ended_refs, payload) {
                errors = errors + 1
                message = message + "invalid-reference:" + payload + ";"
            } else {
                ref := refs[ref_id]
                if lifetime_contains(ended_scopes, ref.owner_name) || lifetime_contains(ended_scopes, ref.scope_name) {
                    errors = errors + 1
                    message = message + "dangling-reference:" + payload + ";"
                } else if kind == "end_borrow" {
                    ended_refs = append(ended_refs, payload)
                }
            }
        } else {
            errors = errors + 1
            message = message + "unknown-lifetime-event:" + kind + ";"
        }
        i = i + 1
    }
    lifetime_check_result { ok: errors == 0, errors: errors, message: message }
}
