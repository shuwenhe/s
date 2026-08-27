package compile.internal.liveness
use std.slices

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
    string[] args_maps
    string[] locals_maps
    string[] stack_objects
}

func plive_emit(string fn_name, live_stack_slot[] slots, int[][]] stack_maps) liveness_emit_blob {
    args_bits := max_bitmap_words(slots, true)
    locals_bits := max_bitmap_words(slots, false)
    args_maps := string[]()
    locals_maps := string[]()
    i := 0
    for i < len(stack_maps) {
        args_maps = append(args_maps, build_bitmap(args_bits, slots, stack_maps[i], true))
        locals_maps = append(locals_maps, build_bitmap(locals_bits, slots, stack_maps[i], false))
        i = i + 1
    }
    liveness_emit_blob {
        args_symbol: fn_name + ".gcargs",
        locals_symbol: fn_name + ".gclocals",
        bitmap_count: len(stack_maps),
        args_bits: args_bits,
        locals_bits: locals_bits,
        args_maps: args_maps,
        locals_maps: locals_maps,
        stack_objects: emit_stack_objects(slots),
    }
}

func max_bitmap_words(live_stack_slot[] slots, bool want_args) int {
    out := 0
    i := 0
    for i < len(slots) {
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

func build_bitmap(int width, live_stack_slot[] slots, int[] live, bool want_args) string {
    if width <= 0 {
        return ""
    }
    bits := int[]()
    i := 0
    for i < width {
        bits = append(bits, 0)
        i = i + 1
    }
    k := 0
    for k < len(slots) && k < len(live) {
        s := slots[k]
        if live[k] != 0 && ((want_args && s.is_arg) || (!want_args && !s.is_arg)) {
            start := slot_word_index(s)
            w := 0
            for w < s.ptr_words {
                idx := start + w
                if idx >= 0 && idx < len(bits) {
                    bits[idx] = 1
                }
                w = w + 1
            }
        }
        k = k + 1
    }
    encode_bitmap(bits)
}

func emit_stack_objects(live_stack_slot[] slots) string[] {
    out := string[]()
    i := 0
    for i < len(slots) {
        s := slots[i]
        if !s.is_arg && s.addr_taken && s.ptr_words > 0 {
            out = append(out, s.name + "@" + to_string(s.frame_offset) + ":" + to_string(s.ptr_words))
        }
        i = i + 1
    }
    out
}

func encode_bitmap(int[] bits) string {
    out := ""
    i := 0
    for i < len(bits) {
        if bits[i] != 0 {
            out = out + "1"
        } else {
            out = out + "0"
        }
        i = i + 1
    }
    out
}
