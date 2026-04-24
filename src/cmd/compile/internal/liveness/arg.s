package compile.internal.liveness

use std.vec.vec

struct arg_liveness_slot {
    string name
    int frame_offset
    int ptr_words
}

struct arg_liveness_payload {
    string symbol_name
    int min_slot_offset
    vec[int] map_offsets
    vec[string] maps
}

func arg_emit_symbol_name(string fn_name) string {
    fn_name + ".argliveinfo"
}

func arg_emit(string fn_name, vec[arg_liveness_slot] args, vec[vec[int]] raw_maps) arg_liveness_payload {
    var maps = dedupe_bitmaps(raw_maps)
    var min_slot_offset = 0
    if args.len() > 0 {
        min_slot_offset = args[0].frame_offset
        var i = 1
        while i < args.len() {
            if args[i].frame_offset < min_slot_offset {
                min_slot_offset = args[i].frame_offset
            }
            i = i + 1
        }
    }
    if min_slot_offset < 0 {
        min_slot_offset = 0
    }
    if min_slot_offset > 255 {
        min_slot_offset = 255
    }

    var map_offsets = vec[int]()
    var encoded_maps = vec[string]()
    var off = min_slot_offset
    var m = 0
    while m < maps.len() {
        var bits = maps[m]
        map_offsets.push(off)
        encoded_maps.push(encode_bitmap(bits))
        off = off + bits.len()
        m = m + 1
    }

    arg_liveness_payload {
        symbol_name: arg_emit_symbol_name(fn_name),
        min_slot_offset: min_slot_offset,
        map_offsets: map_offsets,
        maps: encoded_maps,
    }
}

func dedupe_bitmaps(vec[vec[int]] maps) vec[vec[int]] {
    var out = vec[vec[int]]()
    var i = 0
    while i < maps.len() {
        var seen = false
        var j = 0
        while j < out.len() {
            if bitmap_equal(out[j], maps[i]) {
                seen = true
                break
            }
            j = j + 1
        }
        if !seen {
            out.push(maps[i])
        }
        i = i + 1
    }
    out
}

func bitmap_equal(vec[int] left, vec[int] right) bool {
    if left.len() != right.len() {
        return false
    }
    var i = 0
    while i < left.len() {
        if left[i] != right[i] {
            return false
        }
        i = i + 1
    }
    true
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
