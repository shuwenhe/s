package compile.internal.ownership
use compile.internal.typesys.is_copy_type
use std.slices
func make_decision(string ty) string {
    if is_copy_type(ty) {
        return "copy:" + ty
    }
    "drop:" + ty
}

func make_plan(string[] type_env) string[] {
    string[] plan
    i := 0
    for i < len(type_env) {
        ty := type_env[i]
        next_i := i + 1
        i = next_i
        plan = append(plan, make_decision(ty))
    }
    return plan
}

struct ownership_slot {
    string name
    string type_name
    bool moved
    bool dropped
}

struct ownership_result {
    bool ok
    int errors
    string message
    string[] drops
}

func ownership_find_slot(ownership_slot[] slots, string name) int {
    i := 0
    for i < len(slots) {
        if slots[i].name == name { return i }
        i = i + 1
    }
    -1
}

func ownership_event_colon(string event) int {
    i := 0
    for i < len(event) {
        if string(event[i]) == ":" { return i }
        i = i + 1
    }
    -1
}

func ownership_contains(string[] names, string name) bool {
    i := 0
    for i < len(names) {
        if names[i] == name { return true }
        i = i + 1
    }
    false
}

func ownership_check_events(string[] events) ownership_result {
    ownership_slot[] slots
    string[] moved
    string[] dropped
    string[] drops
    errors := 0
    message := ""
    i := 0
    for i < len(events) {
        event := events[i]
        if event == "scope_exit" {
            j := len(slots) - 1
            for j >= 0 {
                slot := slots[j]
                available := !ownership_contains(moved, slot.name) && !ownership_contains(dropped, slot.name)
                if available && !is_copy_type(slot.type_name) {
                    drops = append(drops, slot.name)
                    dropped = append(dropped, slot.name)
                }
                j = j - 1
            }
            i = i + 1
            continue
        }
        colon := ownership_event_colon(event)
        if colon <= 0 {
            errors = errors + 1
            message = message + "invalid-event;"
            i = i + 1
            continue
        }
        kind := slice(event, 0, colon)
        payload := slice(event, colon + 1, len(event))
        slot_id := ownership_find_slot(slots, payload)
        if kind == "declare" {
            type_colon := ownership_event_colon(payload)
            if type_colon <= 0 || slot_id >= 0 {
                errors = errors + 1
                message = message + "invalid-declare:" + payload + ";"
            } else {
                name := slice(payload, 0, type_colon)
                type_name := slice(payload, type_colon + 1, len(payload))
                slots = append(slots, ownership_slot { name: name, type_name: type_name, moved: false, dropped: false })
            }
        } else if slot_id < 0 {
            errors = errors + 1
            message = message + "unknown-name:" + payload + ";"
        } else if kind == "move" {
            if ownership_contains(moved, payload) || ownership_contains(dropped, payload) {
                errors = errors + 1
                message = message + "move-after-move:" + payload + ";"
            } else if is_copy_type(slots[slot_id].type_name) {

            } else {
                moved = append(moved, payload)
            }
        } else if kind == "use" {
            if ownership_contains(moved, payload) || ownership_contains(dropped, payload) {
                errors = errors + 1
                message = message + "use-after-move:" + payload + ";"
            }
        } else {
            errors = errors + 1
            message = message + "unknown-event:" + kind + ";"
        }
        i = i + 1
    }
    ownership_result { ok: errors == 0, errors: errors, message: message, drops: drops }
}
