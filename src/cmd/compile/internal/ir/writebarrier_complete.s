package compile.internal.ir.writebarrier

enum wb_kind {
    wb_none
    wb_ptr_write
    wb_slice_write
    wb_array_write
    wb_interface_write
}

struct wb_info {
    i32 instr_id
    wb_kind kind
    i32 target_ptr
    i32 value_ptr
    bool needs_barrier
}

struct wb_inserter {
    wb_info[] barriers
    i32 num_barriers
    bool[] is_heap_allocated
    bool[] is_pointer_type
}

func new_wb_inserter(i32 num_values) wb_inserter* {
    wbi := new(wb_inserter)
    wbi.barriers = new wb_info[]()
    wbi.num_barriers = 0
    wbi.is_heap_allocated = make(bool[], num_values)
    wbi.is_pointer_type = make(bool[], num_values)
    
    for i := i32(0); i < num_values; i += 1 {
        wbi.is_heap_allocated[i] = false
        wbi.is_pointer_type[i] = false
    }
    wbi
}

func (wb_inserter* wbi) mark_heap_allocated(i32 value_id) {
    if value_id >= 0 && value_id < i32(len(wbi.is_heap_allocated)) {
        wbi.is_heap_allocated[value_id] = true
    }
}

func (wb_inserter* wbi) mark_pointer_type(i32 value_id) {
    if value_id >= 0 && value_id < i32(len(wbi.is_pointer_type)) {
        wbi.is_pointer_type[value_id] = true
    }
}

func (wb_inserter* wbi) needs_write_barrier(i32 target_id, i32 value_id) bool {
    if target_id < 0 || target_id >= i32(len(wbi.is_heap_allocated)) {
        return false
    }
    if value_id < 0 || value_id >= i32(len(wbi.is_pointer_type)) {
        return false
    }
    
    return wbi.is_heap_allocated[target_id] && wbi.is_pointer_type[value_id]
}

func (wb_inserter* wbi) insert_ptr_write_barrier(i32 instr_id, i32 target_ptr, i32 value_ptr) {
    if !wbi.needs_write_barrier(target_ptr, value_ptr) {
        return
    }
    
    info := wb_info{
        instr_id: instr_id,
        kind: wb_ptr_write,
        target_ptr: target_ptr,
        value_ptr: value_ptr,
        needs_barrier: true
    }
    wbi.barriers = append(wbi.barriers, info)
    wbi.num_barriers += 1
}

func (wb_inserter* wbi) insert_slice_write_barrier(i32 instr_id, i32 slice_ptr, i32 value_ptr) {
    if !wbi.needs_write_barrier(slice_ptr, value_ptr) {
        return
    }
    
    info := wb_info{
        instr_id: instr_id,
        kind: wb_slice_write,
        target_ptr: slice_ptr,
        value_ptr: value_ptr,
        needs_barrier: true
    }
    wbi.barriers = append(wbi.barriers, info)
    wbi.num_barriers += 1
}

func (wb_inserter* wbi) insert_array_write_barrier(i32 instr_id, i32 array_ptr, i32 value_ptr) {
    if !wbi.needs_write_barrier(array_ptr, value_ptr) {
        return
    }
    
    info := wb_info{
        instr_id: instr_id,
        kind: wb_array_write,
        target_ptr: array_ptr,
        value_ptr: value_ptr,
        needs_barrier: true
    }
    wbi.barriers = append(wbi.barriers, info)
    wbi.num_barriers += 1
}

func (wb_inserter* wbi) insert_interface_write_barrier(i32 instr_id, i32 iface_ptr, i32 value_ptr) {
    if !wbi.needs_write_barrier(iface_ptr, value_ptr) {
        return
    }
    
    info := wb_info{
        instr_id: instr_id,
        kind: wb_interface_write,
        target_ptr: iface_ptr,
        value_ptr: value_ptr,
        needs_barrier: true
    }
    wbi.barriers = append(wbi.barriers, info)
    wbi.num_barriers += 1
}

func (wb_inserter* wbi) get_barriers_for_instruction(i32 instr_id) wb_info[] {
    result := new wb_info[]()
    for info in wbi.barriers {
        if info.instr_id == instr_id {
            result = append(result, info)
        }
    }
    result
}

func (wb_inserter* wbi) get_all_barriers() wb_info[] {
    result := new wb_info[]()
    for info in wbi.barriers {
        result = append(result, info)
    }
    result
}

func (wb_inserter* wbi) barrier_count() i32 {
    return i32(len(wbi.barriers))
}

func (wb_inserter* wbi) generate_barrier_call(wb_info info) string {
    call_str := "runtime.write_barrier("
    
    switch info.kind {
        wb_ptr_write: {
            call_str += "target=" + string(info.target_ptr) + ", value=" + string(info.value_ptr)
        }
        wb_slice_write: {
            call_str += "slice=" + string(info.target_ptr) + ", value=" + string(info.value_ptr)
        }
        wb_array_write: {
            call_str += "array=" + string(info.target_ptr) + ", value=" + string(info.value_ptr)
        }
        wb_interface_write: {
            call_str += "iface=" + string(info.target_ptr) + ", value=" + string(info.value_ptr)
        }
        wb_none: {}
    }
    
    call_str + ")"
}

func (wb_inserter* wbi) to_string() string {
    s := "Write Barrier Inserter:\n"
    s += "Total barriers: " + string(wbi.num_barriers) + "\n"
    for info in wbi.barriers {
        s += "  Instr[" + string(info.instr_id) + "]: "
        switch info.kind {
            wb_ptr_write: { s += "PtrWrite" }
            wb_slice_write: { s += "SliceWrite" }
            wb_array_write: { s += "ArrayWrite" }
            wb_interface_write: { s += "InterfaceWrite" }
            wb_none: { s += "None" }
        }
        s += "(target=" + string(info.target_ptr) + ", value=" + string(info.value_ptr) + ")\n"
    }
    s
}
