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
    args_bits := max_bitmap_words(slots, true)
    locals_bits := max_bitmap_words(slots, false)
    args_maps := vec[string]()
    locals_maps := vec[string]()
    i := 0
    for i < stack_maps.len() {
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
    out := 0
    i := 0
    for i < slots.len() {
        s := slots[i]
        if (want_args && s.is_arg) || (!want_args && !s.is_arg) {
            start := slot_word_index(s)
            end := start + s.ptr_words
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
    bits := vec[int]()
    i := 0
    for i < width {
        bits.push(0)
        i = i + 1
    }
    k := 0
    for k < slots.len() && k < live.len() {
        s := slots[k]
        if live[k] != 0 && ((want_args && s.is_arg) || (!want_args && !s.is_arg)) {
            start := slot_word_index(s)
            w := 0
            for w < s.ptr_words {
                idx := start + w
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
    out := vec[string]()
    i := 0
    for i < slots.len() {
        s := slots[i]
        if !s.is_arg && s.addr_taken && s.ptr_words > 0 {
            out.push(s.name + "@" + to_string(s.frame_offset) + ":" + to_string(s.ptr_words))
        }
        i = i + 1
    }
    out
}

func encode_bitmap(vec[int] bits) string {
    out := ""
    i := 0
    for i < bits.len() {
        if bits[i] != 0 {
            out = out + "1"
        } else {
            out = out + "0"
        }
        i = i + 1
    }
    out
}
