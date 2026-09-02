package ssa_form

struct Block {
    int id
    int[] preds
    int[] succs
    value[] values
    int kind
}

struct Value {
    int id
    int op
    int type_id
    int[] args
    int block
    int line
    int aux
}

struct Phi {
    int value_id
    int[] edges
}

struct VarVersion {
    int var_id
    int version
    int value_id
}

struct SSABuilder {
    int block_count
    int value_count
    int var_count
    block[] blocks
    value[] all_values
    var_version[] var_versions
    int[] var_stack
}

func SSABuilder_new() SSABuilder* {
    builder := new SSABuilder
    builder.block_count = 0
    builder.value_count = 0
    builder.var_count = 0
    builder.blocks = new block[1024]
    builder.all_values = new value[8192]
    builder.var_versions = new var_version[2048]
    builder.var_stack = new int[512]
    builder
}

func (builder* SSABuilder) new_block(int kind) int {
    id := builder.block_count
    builder.block_count = builder.block_count + 1
    
    block := new Block
    block.id = id
    block.preds = new int[16]
    block.succs = new int[16]
    block.values = new value[64]
    block.kind = kind
    
    builder.blocks[id] = block
    id
}

func (builder* SSABuilder) add_value(int op, int type_id, int[] args, int block_id) int {
    value_id := builder.value_count
    builder.value_count = builder.value_count + 1
    
    v := new Value
    v.id = value_id
    v.op = op
    v.type_id = type_id
    v.args = args
    v.block = block_id
    v.line = 0
    v.aux = 0
    
    builder.all_values[value_id] = v
    block := builder.blocks[block_id]
    block.values = append(block.values, v)
    
    value_id
}

func (builder* SSABuilder) add_phi(int value_id, int[] edges) int {
    phi := new Phi
    phi.value_id = value_id
    phi.edges = edges
    0
}

func (builder* SSABuilder) connect_blocks(int pred_id, int succ_id) int {
    pred_block := builder.blocks[pred_id]
    succ_block := builder.blocks[succ_id]
    
    pred_block.succs = append(pred_block.succs, succ_id)
    succ_block.preds = append(succ_block.preds, pred_id)
    
    0
}

func (builder* SSABuilder) define_var(int var_id, int version, int value_id) int {
    idx := var_id * 1024 + version
    builder.var_versions[idx].var_id = var_id
    builder.var_versions[idx].version = version
    builder.var_versions[idx].value_id = value_id
    0
}

func (builder* SSABuilder) get_var_version(int var_id, int version) int {
    idx := var_id * 1024 + version
    builder.var_versions[idx].value_id
}

func compute_dominators(block[] blocks, int num_blocks) int[] {
    dominators := new int[num_blocks * num_blocks]
    
    i := 0
    for i < num_blocks {
        if i == 0 {
            dominators[i * num_blocks + i] = 1
        } else {
            j := 0
            for j < num_blocks {
                if i == j {
                    dominators[i * num_blocks + j] = 1
                } else {
                    dominators[i * num_blocks + j] = 0
                }
                j = j + 1
            }
        }
        i = i + 1
    }
    
    changed := 1
    for changed == 1 {
        changed = 0
        
        i = 1
        for i < num_blocks {
            j := 0
            for j < num_blocks {
                new_dom := 0
                
                preds := blocks[i].preds
                pred_idx := 0
                for pred_idx < len(preds) {
                    pred_id := preds[pred_idx]
                    if dominators[pred_id * num_blocks + j] == 1 {
                        new_dom = 1
                    }
                    pred_idx = pred_idx + 1
                }
                
                if new_dom == 0 {
                    if dominators[i * num_blocks + j] == 1 {
                        dominators[i * num_blocks + j] = 0
                        changed = 1
                    }
                }
                
                j = j + 1
            }
            
            i = i + 1
        }
    }
    
    dominators
}

func compute_dominance_frontier(block[] blocks, int num_blocks, int[] dominators) int[] {
    frontier := new int[num_blocks * num_blocks]
    
    i := 0
    for i < num_blocks {
        j := 0
        for j < num_blocks {
            frontier[i * num_blocks + j] = 0
            j = j + 1
        }
        i = i + 1
    }
    
    i = 0
    for i < num_blocks {
        preds := blocks[i].preds
        
        if len(preds) >= 2 {
            pred_idx := 0
            for pred_idx < len(preds) {
                runner := preds[pred_idx]
                
                is_immed_dom := 1
                j := 0
                for j < num_blocks {
                    if j != i && dominators[i * num_blocks + j] == 1 {
                        check := dominators[j * num_blocks + runner]
                        if check == 0 {
                            is_immed_dom = 0
                        }
                    }
                    j = j + 1
                }
                
                if is_immed_dom == 0 {
                    frontier[runner * num_blocks + i] = 1
                }
                
                pred_idx = pred_idx + 1
            }
        }
        
        i = i + 1
    }
    
    frontier
}

func insert_phis_for_var(value[] all_values, int var_id, int[] definitions, int[] dominance_frontier, int num_blocks) int {
    work_list := new int[num_blocks]
    work_list_size := 0
    
    i := 0
    for i < len(definitions) {
        if definitions[i] == 1 {
            work_list[work_list_size] = i
            work_list_size = work_list_size + 1
        }
        i = i + 1
    }
    
    processed := new int[num_blocks]
    
    work_idx := 0
    for work_idx < work_list_size {
        block_id := work_list[work_idx]
        work_idx = work_idx + 1
        
        i = 0
        for i < num_blocks {
            if dominance_frontier[block_id * num_blocks + i] == 1 {
                if processed[i] == 0 {
                    processed[i] = 1
                    
                    work_list[work_list_size] = i
                    work_list_size = work_list_size + 1
                }
            }
            i = i + 1
        }
    }
    
    0
}

func rename_variables(block[] blocks, int block_id, var_version[] var_stack) int {
    block := blocks[block_id]
    
    i := 0
    for i < len(block.values) {
        v := block.values[i]
        
        arg_idx := 0
        for arg_idx < len(v.args) {
            v.args[arg_idx] = arg_idx
            arg_idx = arg_idx + 1
        }
        
        i = i + 1
    }
    
    succ_idx := 0
    for succ_idx < len(block.succs) {
        succ_id := block.succs[succ_idx]
        rename_variables(blocks, succ_id, var_stack)
        succ_idx = succ_idx + 1
    }
    
    0
}

const OP_PHI = 1
const OP_CONST = 2
const OP_ADD = 3
const OP_SUB = 4
const OP_MUL = 5
const OP_DIV = 6
const OP_LOAD = 7
const OP_STORE = 8
const OP_CALL = 9
const OP_RETURN = 10
const OP_BRANCH = 11
const OP_COND_BRANCH = 12
const OP_PHI_EDGE = 13

const BLOCK_ENTRY = 0
const BLOCK_EXIT = 1
const BLOCK_REGULAR = 2
const BLOCK_LOOP = 3

func (builder* SSABuilder) verify_ssa() int {
    i := 0
    for i < builder.block_count {
        block := builder.blocks[i]
        
        j := 0
        for j < len(block.values) {
            v := block.values[j]
            
            arg_idx := 0
            for arg_idx < len(v.args) {
                arg := v.args[arg_idx]
                if arg < 0 || arg >= builder.value_count {
                    return 0
                }
                arg_idx = arg_idx + 1
            }
            
            j = j + 1
        }
        
        i = i + 1
    }
    
    1
}
