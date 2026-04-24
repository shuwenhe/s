package compile.internal.liveness

use std.vec.vec

struct live_stack_slot {
    string name
    int frame_offset
    int ptr_words
    bool is_arg
    bool addr_taken
}

struct liveness_emit_blob {
    string args_symbol
    string locals_symbol
    int bitmap_count
    int args_bits
    int locals_bits
    vec[string] args_maps
    vec[string] locals_maps
    vec[string] stack_objects
}

func plive_emit(string fn_name, vec[live_stack_slot] slots, vec[vec[int]] stack_maps) liveness_emit_blob {
    var args_bits = max_bitmap_words(slots, true)
    var locals_bits = max_bitmap_words(slots, false)

    var args_maps = vec[string]()
    var locals_maps = vec[string]()
    var i = 0
    while i < stack_maps.len() {
        args_maps.push(build_bitmap(args_bits, slots, stack_maps[i], true))
        locals_maps.push(build_bitmap(locals_bits, slots, stack_maps[i], false))
        i = i + 1
    }

    liveness_emit_blob {
        args_symbol: fn_name + ".gcargs",
        locals_symbol: fn_name + ".gclocals",
        bitmap_count: stack_maps.len(),
        args_bits: args_bits,
        locals_bits: locals_bits,
        args_maps: args_maps,
        locals_maps: locals_maps,
        stack_objects: emit_stack_objects(slots),
    }
}

func max_bitmap_words(vec[live_stack_slot] slots, bool want_args) int {
    var out = 0
    var i = 0
    while i < slots.len() {
        var s = slots[i]
        if (want_args && s.is_arg) || (!want_args && !s.is_arg) {
            var start = slot_word_index(s)
            var end = start + s.ptr_words
            if end > out {
                out = end
            }
        }
        i = i + 1
    }
    out
}

func slot_word_index(live_stack_slot slot) int {
    if slot.frame_offset >= 0 {
        return slot.frame_offset / 8
    }
    (-slot.frame_offset) / 8
}

func build_bitmap(int width, vec[live_stack_slot] slots, vec[int] live, bool want_args) string {
    if width <= 0 {
        return ""
    }
    var bits = vec[int]()
    var i = 0
    while i < width {
        bits.push(0)
        i = i + 1
    }

    var k = 0
    while k < slots.len() && k < live.len() {
        var s = slots[k]
        if live[k] != 0 && ((want_args && s.is_arg) || (!want_args && !s.is_arg)) {
            var start = slot_word_index(s)
            var w = 0
            while w < s.ptr_words {
                var idx = start + w
                if idx >= 0 && idx < bits.len() {
                    bits[idx] = 1
                }
                w = w + 1
            }
        }
        k = k + 1
    }

    encode_bitmap(bits)
}

func emit_stack_objects(vec[live_stack_slot] slots) vec[string] {
    var out = vec[string]()
    var i = 0
    while i < slots.len() {
        var s = slots[i]
        if !s.is_arg && s.addr_taken && s.ptr_words > 0 {
            out.push(s.name + "@" + to_string(s.frame_offset) + ":" + to_string(s.ptr_words))
        }
        i = i + 1
    }
    out
}

func encode_bitmap(vec[int] bits) string {
    var out = ""
    var i = 0
    while i < bits.len() {
        if bits[i] != 0 {
            out = out + "1"
        } else {
            out = out + "0"
        }
        i = i + 1
    }
    out
}
