package compile.internal.amd64

struct arch_info {
	string link_arch
	int reg_sp
	int max_width
	string zero_range_hook
	string ginsnop_hook
	string ssa_mark_moves_hook
	string ssa_gen_value_hook
	string ssa_gen_block_hook
	string load_reg_result_hook
	string spill_arg_reg_hook
}

struct prog {
	string op
	string from
	string to
	int offset
}

struct ssa_value {
	string op
	vec[string] args
	bool flags
	bool marked
	string aux
	int reg
}

struct ssa_block {
	vec[ssa_value] values
	vec[ssa_value] controls
	bool flags_live_at_end
}

func init() () {
}

func init_arch_info() arch_info {
	let info = arch_info {
		link_arch: "",
		reg_sp: 0,
		max_width: 0,
		zero_range_hook: "",
		ginsnop_hook: "",
		ssa_mark_moves_hook: "",
		ssa_gen_value_hook: "",
		ssa_gen_block_hook: "",
		load_reg_result_hook: "",
		spill_arg_reg_hook: "",
	}
	return init_amd64(info)
}
