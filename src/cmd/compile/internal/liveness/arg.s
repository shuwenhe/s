package compile.internal.liveness
use std.slices
struct arg_liveness_slot {
    string name
    int frame_offset
    int ptr_words
}

struct arg_liveness_payload {
    string symbol_name
    int min_slot_offset
    int[] map_offsets
    string[] maps
}

func arg_emit_symbol_name(string fn_name) string {
    fn_name + ".argliveinfo"
}

func arg_emit(string fn_name, arg_liveness_slot[] args, int[][]] raw_maps) arg_liveness_payload {
    maps := dedupe_bitmaps(raw_maps)
    min_slot_offset := 0
    if len(args) > 0 {
        min_slot_offset = args[0].frame_offset
        i := 1
        for i < len(args) {
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
    map_offsets := int[]()
    encoded_maps := string[]()
    off := min_slot_offset
    m := 0
    for m < len(maps) {
        bits := maps[m]
        map_offsets = append(map_offsets, off)
        encoded_maps = append(encoded_maps, encode_bitmap(bits))
        off = off + len(bits)
        m = m + 1
    }
    arg_liveness_payload {
        symbol_name: arg_emit_symbol_name(fn_name),
        min_slot_offset: min_slot_offset,
        map_offsets: map_offsets,
        maps: encoded_maps,
    }
}

func dedupe_bitmaps(int[][]] maps) int[][]] {
    out := int[][]]()
    i := 0
    for i < len(maps) {
        seen := false
        j := 0
        for j < len(out) {
            if bitmap_equal(out[j], maps[i]) {
                seen = true
                break
            }
            j = j + 1
        }
        if !seen {
            out = append(out, maps[i])
        }
        i = i + 1
    }
    out
}

func bitmap_equal(int[] left, int[] right) bool {
    if len(left) != len(right) {
        return false
    }
    i := 0
    for i < len(left) {
        if left[i] != right[i] {
            return false
        }
        i = i + 1
    }
    true
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
