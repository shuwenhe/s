package compile.internal.link
enum addr_type {
    addr_type_none,
    addr_type_const,
    addr_type_reg,
    addr_type_mem,
    addr_type_branch,
    addr_type_special,
}
struct addr {
    addr_type type
    int reg
    int index
    int scale
    int64 offset
    string sym
    int64 symoff
}

func make_addr_const(int64 offset) addr {
    addr {
        type: addr_type_const, offset offset,
    }
}

func make_addr_reg(int reg) addr {
    addr {
        type: addr_type_reg, reg reg,
    }
}

func make_addr_mem(int base_reg, int64 offset) addr {
    addr {
        type: addr_type_mem, reg base_reg, offset offset,
    }
}

func make_addr_indexed(int base_reg, int index_reg, int scale, int64 offset) addr {
    addr {
        type: addr_type_mem, reg base_reg, index index_reg, scale scale, offset offset,
    }
}

func make_addr_sym(string sym, int64 offset) addr {
    addr {
        type: addr_type_mem, sym sym, symoff offset,
    }
}

func make_addr_branch(string label) addr {
    addr {
        type: addr_type_branch, sym label,
    }
}

func (a* addr) string_repr() string {
    switch a.type {
        case addr_type_const: return a.offset as string
        case addr_type_reg: return "r" + (a.reg as string)
        case addr_type_mem: {
            result := ""
            if a.sym != "" {
                result = a.sym
            }
            if a.offset != 0 {
                result = result + "+" + (a.offset as string)
            }
            if a.reg != 0 {
                result = result + "(" + ("r" + (a.reg as string)) + ")"
            }
            if a.index != 0 {
                result = result + "(" + ("r" + (a.index as string)) + "*" + (a.scale as string) + ")"
            }
            return result
        }
        case addr_type_branch: return "label:" + a.sym
        case addr_type_special: return "special:" + a.sym
    }
    "unknown"
}
