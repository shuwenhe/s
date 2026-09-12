package compile.internal.ownership_with_fields

use compile.internal.typesys.is_copy_type
use compile.internal.field_virtualization.field_encode_virtual_name
use compile.internal.field_virtualization.field_decode_virtual_name
use std.slices

struct ownership_slot_ext {
    name string
    type_name string
    moved bool
    dropped bool
    base_var string
    field_name string
    is_virtual_field bool
}

struct ownership_result_ext {
    ok bool
    errors int
    message string
    string[] drops
    string[] field_moves
}

func ownership_find_slot_ext(ownership_slot_ext[] slots, string name) int {
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

func field_move_key(string base_var, string field_name) string {
    base_var + "." + field_name
}

func is_field_moved(string[] field_moves, string base_var, string field_name) bool {
    key := field_move_key(base_var, field_name)
    ownership_contains(field_moves, key)
}

func ownership_check_events_ext(string[] events) ownership_result_ext {
    ownership_slot_ext[] slots
    string[] moved
    string[] dropped
    string[] drops
    string[] field_moves
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

                if slot.is_virtual_field {
                    if is_field_moved(field_moves, slot.base_var, slot.field_name) {
                        available = false
                    }
                }

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
        slot_id := ownership_find_slot_ext(slots, payload)

        if kind == "declare" {
            type_colon := ownership_event_colon(payload)
            if type_colon <= 0 || slot_id >= 0 {
                errors = errors + 1
                message = message + "invalid-declare:" + payload + ";"
            } else {
                name := slice(payload, 0, type_colon)
                type_name := slice(payload, type_colon + 1, len(payload))

                base, field := field_decode_virtual_name(name)
                is_vfield := base != "" && field != ""

                slot := ownership_slot_ext {
                    name: name,
                    type_name: type_name,
                    moved: false,
                    dropped: false,
                    base_var: base,
                    field_name: field,
                    is_virtual_field: is_vfield
                }
                slots = append(slots, slot)
            }
        } else if slot_id < 0 {
            errors = errors + 1
            message = message + "unknown-name:" + payload + ";"
        } else if kind == "move" {
            slot := slots[slot_id]

            if ownership_contains(moved, payload) || ownership_contains(dropped, payload) {
                errors = errors + 1
                message = message + "move-after-move:" + payload + ";"
            } else if is_copy_type(slot.type_name) {

            } else {
                moved = append(moved, payload)

                if slot.is_virtual_field {
                    key := field_move_key(slot.base_var, slot.field_name)
                    field_moves = append(field_moves, key)
                }
            }
        } else if kind == "clone" {
            if ownership_contains(moved, payload) || ownership_contains(dropped, payload) {
                errors = errors + 1
                message = message + "clone-after-move:" + payload + ";"
            }
        } else if kind == "use" {
            slot := slots[slot_id]

            if ownership_contains(moved, payload) || ownership_contains(dropped, payload) {
                errors = errors + 1
                message = message + "use-after-move:" + payload + ";"
            } else if slot.is_virtual_field && is_field_moved(field_moves, slot.base_var, slot.field_name) {
                errors = errors + 1
                message = message + "use-after-field-move:" + payload + ";"
            }
        } else {
            errors = errors + 1
            message = message + "unknown-event:" + kind + ";"
        }

        i = i + 1
    }

    ownership_result_ext {
        ok: errors == 0,
        errors: errors,
        message: message,
        drops: drops,
        field_moves: field_moves
    }
}