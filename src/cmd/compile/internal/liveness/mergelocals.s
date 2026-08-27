package compile.internal.liveness
use std.slices

struct local_slot {
    string name
    int size
    int ptr_words
    int align
    int offset
}

struct merged_locals {
    local_slot[] slots
    int frame_size
}

func merge_locals(local_slot[] a, local_slot[] b) merged_locals {
    slots := local_slot[]()
    append_unique_slots(slots, a)
    append_unique_slots(slots, b)
    cursor := 0
    i := 0
    for i < len(slots) {
        align := slots[i].align
        if align <= 0 {
            align = 8
        }
        cursor = align_up(cursor, align)
        slots[i].offset = cursor
        cursor = cursor + slots[i].size
        i = i + 1
    }
    merged_locals {
        slots: slots,
        frame_size: align_up(cursor, 8),
    }
}

func append_unique_slots(local_slot[] dst, local_slot[] src) () {
    i := 0
    for i < len(src) {
        idx := find_slot_index(dst, src[i].name)
        if idx < 0 {
            dst = append(dst, src[i])
        } else {
            if src[i].size > dst[idx].size {
                dst[idx].size = src[i].size
            }
            if src[i].ptr_words > dst[idx].ptr_words {
                dst[idx].ptr_words = src[i].ptr_words
            }
            if src[i].align > dst[idx].align {
                dst[idx].align = src[i].align
            }
        }
        i = i + 1
    }
}

func find_slot_index(local_slot[] slots, string name) int {
    i := 0
    for i < len(slots) {
        if slots[i].name == name {
            return i
        }
        i = i + 1
    }
    -1
}

func align_up(int value, int align) int {
    if align <= 1 {
        return value
    }
    ((value + align - 1) / align) * align
}
