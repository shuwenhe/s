package compile.internal.amd64
struct arch_info {
	link_arch string
	reg_sp int
	max_width int
	zero_range_hook string
	ginsnop_hook string
	ssa_mark_moves_hook string
	ssa_gen_value_hook string
	ssa_gen_block_hook string
	load_reg_result_hook string
	spill_arg_reg_hook string
}

struct prog {
	op string
	from string
	to string
	offset int
}

struct ssa_value {
	op string
	string[] args
	flags bool
	marked bool
	aux string
	reg int
}

struct ssa_block {
	ssa_value[] values
	ssa_value[] controls
	flags_live_at_end bool
}

func init() () {
}

func init_arch_info() arch_info {
	info := arch_info {
		link_arch: "", reg_sp 0, max_width 0,
		zero_range_hook: "",
		ginsnop_hook: "",
		ssa_mark_moves_hook: "",
		ssa_gen_value_hook: "",
		ssa_gen_block_hook: "",
		load_reg_result_hook: "",
		spill_arg_reg_hook: "",
	}
	return init_amd64(info
}