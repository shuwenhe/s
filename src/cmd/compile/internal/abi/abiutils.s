package compile.internal.abi

use std.vec.vec

struct reg_amounts {
    int int_regs
    int float_regs
}

struct abi_config {
    int offset_for_locals
    reg_amounts reg_amounts
    int which
}

struct abi_param_assignment {
    string type_name
    string name
    vec[int] registers
    int offset
}

struct abi_param_result_info {
    vec[abi_param_assignment] inparams
    vec[abi_param_assignment] outparams
    int offset_to_spill_area
    int spill_area_size
    int in_registers_used
    int out_registers_used
    abi_config config
}

struct register_layout {
    vec[string] types
    vec[int] offsets
}

struct assign_state {
    reg_amounts r_total
    reg_amounts r_used
    int stack_offset
    int spill_offset
}

struct reg_alloc_result {
    bool ok
    vec[int] regs
}

func new_abi_config(int i_regs_count, int f_regs_count, int offset_for_locals, int which) abi_config {
    abi_config {
        offset_for_locals: offset_for_locals,
        reg_amounts: reg_amounts {
            int_regs: i_regs_count,
            float_regs: f_regs_count,
        },
        which: which,
    }
}

func config_which(abi_config config) int {
    config.which
}

func locals_offset(abi_config config) int {
    config.offset_for_locals
}

func float_index_for(abi_config config, int r) int {
    r - config.reg_amounts.int_regs
}

func in_params(abi_param_result_info info) vec[abi_param_assignment] {
    info.inparams
}

func out_params(abi_param_result_info info) vec[abi_param_assignment] {
    info.outparams
}

func in_param(abi_param_result_info info, int index) abi_param_assignment {
    info.inparams[index]
}

func out_param(abi_param_result_info info, int index) abi_param_assignment {
    info.outparams[index]
}

func spill_area_offset(abi_param_result_info info) int {
    info.offset_to_spill_area
}

func spill_area_size(abi_param_result_info info) int {
    info.spill_area_size
}

func in_registers_used(abi_param_result_info info) int {
    info.in_registers_used
}

func out_registers_used(abi_param_result_info info) int {
    info.out_registers_used
}

func arg_width(abi_param_result_info info) int {
    info.spill_area_size + info.offset_to_spill_area - locals_offset(info.config)
}

func abi_param_offset(abi_param_assignment assignment) int {
    if assignment.registers.len() > 0 {
        return -1
    }
    assignment.offset
}

func frame_offset(abi_param_assignment assignment, abi_param_result_info info) int {
    if assignment.offset < 0 {
        return -1
    }
    if assignment.registers.len() == 0 {
        return assignment.offset - locals_offset(info.config)
    }
    assignment.offset + spill_area_offset(info) - locals_offset(info.config)
}

func reg_string(reg_amounts amounts, int r) string {
    if r < amounts.int_regs {
        return "I" + to_string(r)
    }
    if r < amounts.int_regs + amounts.float_regs {
        return "F" + to_string(r - amounts.int_regs)
    }
    "<?>" + to_string(r)
}

func assignment_string(abi_param_assignment assignment, abi_config config, bool extra) string {
    var regs = "R{"
    var offname = "spilloffset"
    if assignment.registers.len() == 0 {
        offname = "offset"
    }
    var i = 0
    while i < assignment.registers.len() {
        var r = assignment.registers[i]
        regs = regs + " " + reg_string(config.reg_amounts, r)
        if extra {
            regs = regs + "(" + to_string(r) + ")"
        }
        i = i + 1
    }
    if extra {
        regs = regs + " | #I=" + to_string(config.reg_amounts.int_regs) + " #F=" + to_string(config.reg_amounts.float_regs)
    }
    regs + " } " + offname + ": " + to_string(assignment.offset) + " typ: " + assignment.type_name
}

func info_string(abi_param_result_info info) string {
    var out = ""
    var i = 0
    while i < info.inparams.len() {
        out = out + "IN " + to_string(i) + ": " + assignment_string(info.inparams[i], info.config, false) + "\n"
        i = i + 1
    }
    i = 0
    while i < info.outparams.len() {
        out = out + "OUT " + to_string(i) + ": " + assignment_string(info.outparams[i], info.config, false) + "\n"
        i = i + 1
    }
    out + "offsetToSpillArea: " + to_string(info.offset_to_spill_area) + " spillAreaSize: " + to_string(info.spill_area_size)
}

func num_param_regs(abi_config config, string type_name) int {
    var need = reg_amounts_for_type(type_name)
    if need.int_regs > config.reg_amounts.int_regs || need.float_regs > config.reg_amounts.float_regs {
        return -1
    }
    need.int_regs + need.float_regs
}

func abi_analyze_types(abi_config config, vec[string] params, vec[string] results) abi_param_result_info {
    var state = assign_state {
        r_total: config.reg_amounts,
        r_used: reg_amounts { int_regs: 0, float_regs: 0 },
        stack_offset: config.offset_for_locals,
        spill_offset: 0,
    }

    var inparams = vec[abi_param_assignment]()
    var i = 0
    while i < params.len() {
        inparams.push(assign_param(state, params[i], "", false))
        i = i + 1
    }
    state.stack_offset = align_to(state.stack_offset, reg_size())
    var in_regs_used = state.r_used.int_regs + state.r_used.float_regs

    state.r_used = reg_amounts { int_regs: 0, float_regs: 0 }
    var outparams = vec[abi_param_assignment]()
    i = 0
    while i < results.len() {
        outparams.push(assign_param(state, results[i], "", true))
        i = i + 1
    }

    abi_param_result_info {
        inparams: inparams,
        outparams: outparams,
        offset_to_spill_area: align_to(state.stack_offset, reg_size()),
        spill_area_size: align_to(state.spill_offset, reg_size()),
        in_registers_used: in_regs_used,
        out_registers_used: state.r_used.int_regs + state.r_used.float_regs,
        config: config,
    }
}

func register_types(vec[abi_param_assignment] assignments) vec[string] {
    var rts = vec[string]()
    var i = 0
    while i < assignments.len() {
        if assignments[i].registers.len() > 0 {
            rts = append_param_types(rts, assignments[i].type_name)
        }
        i = i + 1
    }
    rts
}

func register_types_and_offsets(abi_param_assignment assignment) register_layout {
    if assignment.registers.len() == 0 {
        return register_layout {
            types: vec[string](),
            offsets: vec[int](),
        }
    }

    var types = append_param_types(vec[string](), assignment.type_name)
    var pair = append_param_offsets(vec[int](), 0, assignment.type_name)
    register_layout {
        types: types,
        offsets: pair.offsets,
    }
}

func compute_padding(abi_param_assignment assignment, int slots) vec[int] {
    var padding = vec[int]()
    var i = 0
    while i < slots {
        padding.push(0)
        i = i + 1
    }
    if assignment.registers.len() == 0 {
        return padding
    }

    var layout = register_types_and_offsets(assignment)
    i = 0
    while i + 1 < layout.types.len() && i < padding.len() {
        var at = layout.offsets[i] + type_size(layout.types[i])
        var next = layout.offsets[i + 1]
        if next > at {
            padding.set(i, next - at)
        }
        i = i + 1
    }
    padding
}

struct offset_result {
    vec[int] offsets
    int next
}

func append_param_offsets(vec[int] offsets, int at, string type_name) offset_result {
    var size = type_size(type_name)
    if size == 0 {
        return offset_result { offsets: offsets, next: at }
    }

    if is_complex_type(type_name) || size > reg_size() {
        var half = size / 2
        offsets.push(at)
        offsets.push(at + half)
        return offset_result { offsets: offsets, next: at + size }
    }

    offsets.push(at)
    offset_result { offsets: offsets, next: at + size }
}

func append_param_types(vec[string] rts, string type_name) vec[string] {
    if type_size(type_name) == 0 {
        return rts
    }
    if is_complex_type(type_name) {
        rts.push("float")
        rts.push("float")
        return rts
    }
    if is_float_type(type_name) {
        rts.push("float")
        return rts
    }
    if is_string_type(type_name) {
        rts.push("ptr")
        rts.push("int")
        return rts
    }
    if is_slice_type(type_name) {
        rts.push("ptr")
        rts.push("int")
        rts.push("int")
        return rts
    }
    if is_interface_type(type_name) {
        rts.push("ptr")
        rts.push("ptr")
        return rts
    }
    if type_size(type_name) > reg_size() {
        rts.push("uint32")
        rts.push("uint32")
        return rts
    }
    rts.push(type_name)
    rts
}

func assign_param(assign_state mut state, string type_name, string name, bool is_result) abi_param_assignment {
    var alloc = try_alloc_regs(state, type_name)
    var offset = -1
    if !alloc.ok {
        offset = next_slot(state.stack_offset, type_name)
        state.stack_offset = align_to(offset + type_size(type_name), alignment_for_type(type_name))
    } else if !is_result {
        offset = next_slot(state.spill_offset, type_name)
        state.spill_offset = align_to(offset + type_size(type_name), alignment_for_type(type_name))
    }

    abi_param_assignment {
        type_name: type_name,
        name: name,
        registers: alloc.regs,
        offset: offset,
    }
}

func try_alloc_regs(assign_state mut state, string type_name) reg_alloc_result {
    if type_size(type_name) == 0 {
        return reg_alloc_result { ok: false, regs: vec[int]() }
    }

    var need = reg_amounts_for_type(type_name)
    if need.int_regs > state.r_total.int_regs - state.r_used.int_regs {
        return reg_alloc_result { ok: false, regs: vec[int]() }
    }
    if need.float_regs > state.r_total.float_regs - state.r_used.float_regs {
        return reg_alloc_result { ok: false, regs: vec[int]() }
    }

    var regs = vec[int]()
    var i = 0
    while i < need.int_regs {
        regs.push(state.r_used.int_regs + i)
        i = i + 1
    }
    i = 0
    while i < need.float_regs {
        regs.push(state.r_total.int_regs + state.r_used.float_regs + i)
        i = i + 1
    }

    state.r_used.int_regs = state.r_used.int_regs + need.int_regs
    state.r_used.float_regs = state.r_used.float_regs + need.float_regs
    reg_alloc_result { ok: true, regs: regs }
}

func next_slot(int offset, string type_name) int {
    align_to(offset, alignment_for_type(type_name))
}

func reg_amounts_for_type(string type_name) reg_amounts {
    if is_zero_size_type(type_name) {
        return reg_amounts { int_regs: 0, float_regs: 0 }
    }
    if is_complex_type(type_name) {
        return reg_amounts { int_regs: 0, float_regs: 2 }
    }
    if is_float_type(type_name) {
        return reg_amounts { int_regs: 0, float_regs: 1 }
    }
    if is_string_type(type_name) {
        return reg_amounts { int_regs: 2, float_regs: 0 }
    }
    if is_slice_type(type_name) {
        return reg_amounts { int_regs: 3, float_regs: 0 }
    }
    if is_interface_type(type_name) {
        return reg_amounts { int_regs: 2, float_regs: 0 }
    }

    var words = (type_size(type_name) + reg_size() - 1) / reg_size()
    if words < 1 {
        words = 1
    }
    reg_amounts { int_regs: words, float_regs: 0 }
}

func reg_size() int {
    8
}

func type_size(string type_name) int {
    if is_zero_size_type(type_name) {
        return 0
    }
    if type_name == "int" || type_name == "uint" || type_name == "ptr" || type_name == "unsafe_ptr" {
        return 8
    }
    if type_name == "int64" || type_name == "uint64" {
        return 8
    }
    if type_name == "int32" || type_name == "uint32" || type_name == "float32" {
        return 4
    }
    if type_name == "int16" || type_name == "uint16" {
        return 2
    }
    if type_name == "int8" || type_name == "uint8" || type_name == "bool" {
        return 1
    }
    if type_name == "float64" {
        return 8
    }
    if type_name == "complex64" {
        return 8
    }
    if type_name == "complex128" {
        return 16
    }
    if is_string_type(type_name) {
        return 16
    }
    if is_slice_type(type_name) {
        return 24
    }
    if is_interface_type(type_name) {
        return 16
    }
    if is_simd_type(type_name) {
        return 16
    }
    8
}

func alignment_for_type(string type_name) int {
    var size = type_size(type_name)
    if size <= 1 {
        return 1
    }
    if size <= 2 {
        return 2
    }
    if size <= 4 {
        return 4
    }
    8
}

func align_to(int value, int to) int {
    if to <= 0 {
        return value
    }
    var m = value % to
    if m == 0 {
        return value
    }
    value + to - m
}

func is_zero_size_type(string type_name) bool {
    type_name == "" || type_name == "()" || type_name == "unit" || type_name == "struct{}"
}

func is_float_type(string type_name) bool {
    type_name == "float32" || type_name == "float64" || type_name == "float"
}

func is_complex_type(string type_name) bool {
    type_name == "complex64" || type_name == "complex128"
}

func is_simd_type(string type_name) bool {
    starts_with(type_name, "simd")
}

func is_string_type(string type_name) bool {
    type_name == "string"
}

func is_slice_type(string type_name) bool {
    starts_with(type_name, "[]")
}

func is_interface_type(string type_name) bool {
    type_name == "iface" || type_name == "interface" || type_name == "any"
}

func starts_with(string text, string prefix) bool {
    if text.len() < prefix.len() {
        return false
    }
    var i = 0
    while i < prefix.len() {
        if text[i] != prefix[i] {
            return false
        }
        i = i + 1
    }
    true
}
