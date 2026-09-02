# S 编译器工业化实现计划 - 18 周详细路线图

**创建日期**: 2026-09-02  
**总工作量**: 129K LOC，18 周完成  
**目标**: 构建生产级编译器系统，完全独立自举

---

## 阶段划分概览

```
┌─────────────────────────────────────────────────────────────────┐
│ 阶段 1: 完整前端 (Week 1-3) - 自身编译能力                      │
│ ├─ 完整的词法分析器 (Lexer)                                     │
│ ├─ 完整的语法分析器 (Parser)                                    │
│ ├─ 完整的语义分析器 (Semantic)                                  │
│ └─ ✅ 验证: 编译器前端自编译                                    │
├─────────────────────────────────────────────────────────────────┤
│ 阶段 2: 中间层优化 (Week 4-5) - IR 优化能力                     │
│ ├─ 统一 IR 构建器 (Unified IR)                                  │
│ ├─ 控制流分析 (CFG)                                             │
│ ├─ 数据流分析 (DFA)                                             │
│ └─ ✅ 验证: 优化正确性测试 (1000+ 个)                           │
├─────────────────────────────────────────────────────────────────┤
│ 阶段 3: 代码生成 (Week 6-8) - 生成执行代码                      │
│ ├─ 指令选择 (Instruction Selection)                            │
│ ├─ SSA 规则库 (13,000+ 条)                                      │
│ ├─ 寄存器分配 (Graph Coloring)                                  │
│ └─ ✅ 验证: 生成可运行的二进制 (小程序)                         │
├─────────────────────────────────────────────────────────────────┤
│ 阶段 4: 链接器 & 运行时 (Week 9-10) - 完整工具链                │
│ ├─ 纯 S ELF 链接器                                              │
│ ├─ 最小运行时 (malloc/syscall)                                  │
│ └─ ✅ 验证: 编译输出可独立运行                                  │
├─────────────────────────────────────────────────────────────────┤
│ 阶段 5: Stage 2 自编译 (Week 11-12) - 自举验证                 │
│ ├─ Stage 2 完整编译器生成                                       │
│ ├─ 自编译测试                                                   │
│ └─ ✅ 验证: make stage2-check 通过                             │
├─────────────────────────────────────────────────────────────────┤
│ 阶段 6: 真正自举 (Week 13-15) - 纯 S 自举                      │
│ ├─ Stage 2 编译自身                                             │
│ ├─ 二进制对等验证                                               │
│ └─ ✅ 验证: make true-selfhost-check 通过                     │
├─────────────────────────────────────────────────────────────────┤
│ 阶段 7: 生产优化 (Week 16-18) - 性能 & 工具链                   │
│ ├─ SSA 规则优化 (追加 3,000+ 条)                               │
│ ├─ 工具链完善 (dump/disasm/profile)                            │
│ └─ ✅ 验证: 性能基准达成 (100-500× 提升)                       │
└─────────────────────────────────────────────────────────────────┘
```

---

## 阶段 1: 完整前端 (Week 1-3)

### 目标
- 完成 S 语言的词法、语法、语义分析
- 前端自编译（编译器前端部分自身编译成功）
- 生成中间表示 (IR)

### 代码规模
- 总计：16K LOC
- Lexer: 2K LOC
- Parser: 8K LOC
- Semantic: 4K LOC
- 支持库: 2K LOC

### Day 1-2: Lexer (词法分析器)

**目标**: 完整的 S 语言词法分析器，支持所有 Token 类型

```s
// 文件: src/cmd/compile/internal/frontend/lexer.s
// 核心接口:
//   lexer_new(source: string) lexer
//   lexer_next_token(lex: &mut lexer) token
//   token_type_name(t: token) string

package frontend

struct token {
    token_type: int
    value: string
    line: int
    column: int
}

struct lexer {
    source: string
    position: int
    read_position: int
    current_char: char
    line: int
    column: int
}

// Token 类型常量
const TOKEN_EOF = 0
const TOKEN_IDENT = 1
const TOKEN_INT = 2
const TOKEN_FLOAT = 3
const TOKEN_STRING = 4
// ... 50+ 类型

func lexer_new(string source) lexer {
    // 初始化词法分析器
}

func lexer_next_token(lex: &mut lexer) token {
    // 跳过空白和注释
    // 识别 Token
    // 返回下一个 Token
}
```

**子任务**:
- [ ] 定义 50+ Token 类型
- [ ] 实现字符读取和位置跟踪
- [ ] 实现数字、字符串、标识符识别
- [ ] 实现关键字识别
- [ ] 单元测试 (1000+ 个)

**验证**: `make lexer-test` 通过

---

### Day 3-6: Parser (语法分析器)

**目标**: 递归下降解析器，支持完整的 S 语法

```s
// 文件: src/cmd/compile/internal/frontend/parser.s

package frontend

struct ast_node {
    node_type: int
    // 根据 node_type 有不同的字段
}

struct parser {
    lexer: lexer
    current_token: token
    peek_token: token
    errors: string[]
}

// AST Node 类型
const AST_PROGRAM = 1
const AST_PACKAGE = 2
const AST_IMPORT = 3
const AST_FUNC = 4
const AST_STRUCT = 5
// ... 30+ 类型

func parser_new(lex: lexer) parser { }
func parser_parse(p: &mut parser) ast_node { }
func parser_parse_func(p: &mut parser) ast_node { }
func parser_parse_expr(p: &mut parser, int precedence) ast_node { }
```

**子任务**:
- [ ] AST 节点定义
- [ ] 递归下降基础设施
- [ ] 表达式解析（优先级爬升）
- [ ] 语句解析
- [ ] 声明解析（函数、结构体、枚举）
- [ ] 错误恢复机制
- [ ] 单元测试 (2000+ 个)

**验证**: `make parser-test` 通过

---

### Day 7-9: Semantic Analyzer (语义分析)

**目标**: 类型检查、符号解析、可达性分析

```s
// 文件: src/cmd/compile/internal/frontend/semantic.s

package frontend

struct symbol {
    name: string
    symbol_type: int    // VAR, FUNC, STRUCT, ENUM
    value_type: string  // int, string, &T, vec[T], ...
    scope_depth: int
}

struct semantic_analyzer {
    ast: ast_node
    symbols: symbol[]
    scope_stack: int[]  // 作用域深度栈
    errors: string[]
    types: type_info[]
}

func semantic_analyze(ast: &ast_node) semantic_result {
    // 1. 构建符号表
    // 2. 类型检查
    // 3. 可达性分析
    // 4. 生存性检查
    // 返回类型检查后的 AST
}
```

**子任务**:
- [ ] 符号表实现
- [ ] 作用域管理
- [ ] 类型推导
- [ ] 方法查找
- [ ] 泛型处理
- [ ] 错误报告
- [ ] 单元测试 (2000+ 个)

**验证**: `make semantic-test` 通过

---

### Day 10: 支持库 & 集成

**文件**:
- `src/cmd/compile/internal/frontend/ast.s` - AST 定义和工具函数
- `src/cmd/compile/internal/frontend/types.s` - 类型系统
- `src/cmd/compile/internal/frontend/symbols.s` - 符号表管理
- `src/cmd/compile/internal/frontend/errors.s` - 错误处理

**任务**:
- [ ] 集成 Lexer/Parser/Semantic
- [ ] 全系统集成测试
- [ ] 性能基准

**验证**: `make frontend-test` 全部通过

---

### 阶段 1 交付物检查清单

```
前端模块 (src/cmd/compile/internal/frontend/)
├─ ✅ lexer.s ......................... 2K LOC
├─ ✅ parser.s ....................... 8K LOC
├─ ✅ semantic.s ..................... 4K LOC
├─ ✅ ast.s .......................... 1K LOC
├─ ✅ types.s ........................ 1K LOC
└─ ✅ 单元测试 (test/) .............. 5K LOC

总代码量: 16K LOC
单元测试: 1000+ 个
验证: ✅ make stage1-check

里程碑: M1 ✅ 完整前端
```

---

## 阶段 2: 中间层优化 (Week 4-5)

### 目标
- IR 构建和规范化
- 控制流分析和数据流分析
- 优化管道框架

### 代码规模
- 总计：20K LOC
- IR Builder: 6K LOC
- CFG & DFA: 8K LOC
- 优化通道: 6K LOC

### Day 11-13: IR 构建 (IR Builder)

```s
// 文件: src/cmd/compile/internal/middleend/ir_builder.s

package middleend

struct ir_value {
    value_type: int     // CONST, VAR, BINOP, CALL, ...
    value_id: int       // 唯一 ID
    line: int
}

struct ir_instruction {
    opcode: int         // ADD, SUB, MUL, ...
    operands: ir_value[]
    result: ir_value
}

struct ir_basicblock {
    block_id: int
    instructions: ir_instruction[]
    terminator: ir_instruction  // Br / CondBr / Ret
    predecessors: int[]
    successors: int[]
}

struct ir_function {
    name: string
    blocks: ir_basicblock[]
    arguments: ir_value[]
    return_type: string
    cfg: control_flow_graph
}

func build_ir_from_ast(ast: &ast_node) ir_function[] {
    // 遍历 AST
    // 生成 IR
    // 构建 CFG
    // 转换为 SSA 形式
}
```

**子任务**:
- [ ] IR 值、指令、基本块定义
- [ ] AST → IR 转换
- [ ] SSA 形式转换
- [ ] 函数内联前准备
- [ ] 单元测试 (1000+ 个)

**验证**: `make ir-builder-test` 通过

---

### Day 14-16: CFG & DFA (分析框架)

```s
// 文件: src/cmd/compile/internal/middleend/analysis.s

package middleend

struct control_flow_graph {
    entry_block: int
    exit_block: int
    blocks: ir_basicblock[]
    dominators: int[][]      // dominators[i] = i 的支配节点
    idom: int[]              // 直接支配者
    domtree: int[][]         // 支配树
}

struct liveness_info {
    live_in: bitset[]
    live_out: bitset[]
    def: bitset[]
    use: bitset[]
}

func build_cfg(blocks: &ir_basicblock[]) control_flow_graph {
    // 建立块之间的连接
    // 计算后继/前驱
}

func compute_dominators(cfg: &control_flow_graph) {
    // 计算支配树（Lengauer-Tarjan 算法）
}

func compute_liveness(cfg: &control_flow_graph) liveness_info {
    // 反向数据流分析
    // 计算每个指令的活跃变量
}

func compute_reaching_definitions(cfg: &control_flow_graph) reaching_def_info {
    // 前向数据流分析
    // 计算到达定义
}
```

**子任务**:
- [ ] CFG 构建
- [ ] 支配者计算
- [ ] 生存性分析
- [ ] 到达定义分析
- [ ] 使用链构建
- [ ] 单元测试 (1000+ 个)

**验证**: `make analysis-test` 通过

---

### Day 17-19: 优化管道 (Optimization Passes)

```s
// 文件: src/cmd/compile/internal/middleend/optimizer.s

package middleend

struct optimization_pass {
    name: string
    pass_id: int
    dependencies: int[]  // 依赖的分析
}

func opt_constant_folding(func: &ir_function) ir_function {
    // 在编译期计算常数表达式
    // 如: 2 + 3 → 5, x * 1 → x
}

func opt_dead_code_elimination(func: &ir_function, liveness: &liveness_info) ir_function {
    // 移除未使用的指令
}

func opt_global_value_numbering(func: &ir_function) ir_function {
    // 消除重复计算
    // 如: a = b + c; d = b + c; → d = a;
}

func opt_licm(func: &ir_function, cfg: &control_flow_graph) ir_function {
    // Loop Invariant Code Motion
    // 将循环不变式移出循环
}

func opt_inlining(module: &ir_function[], inline_hints: &int[]) ir_function[] {
    // 函数内联（基于启发式）
}

func run_optimization_pipeline(func: &ir_function) ir_function {
    // 按顺序运行优化通道
    // 1. 常数折叠
    // 2. DCE
    // 3. GVN
    // 4. LICM
    // 5. 内联
}
```

**子任务**:
- [ ] 常数折叠实现
- [ ] 死代码消除
- [ ] GVN 实现
- [ ] LICM 实现
- [ ] 内联启发式
- [ ] 单元测试 (1000+ 个)

**验证**: `make optimizer-test` 通过

---

### 阶段 2 交付物检查清单

```
中间层模块 (src/cmd/compile/internal/middleend/)
├─ ✅ ir_builder.s .................. 6K LOC
├─ ✅ analysis.s ................... 8K LOC
├─ ✅ optimizer.s .................. 6K LOC
└─ ✅ 单元测试 (test/) ............ 5K LOC

总代码量: 20K LOC
单元测试: 3000+ 个
验证: ✅ make middleend-test

里程碑: M2 ✅ 中间层优化
```

---

## 阶段 3: 代码生成 (Week 6-8)

### 目标
- 指令选择系统
- SSA 规则库 (13,000+ 条)
- 寄存器分配
- 汇编生成

### 代码规模
- 总计：28K LOC
- SSA 规则库: 15K LOC
- 指令选择: 5K LOC
- 寄存器分配: 5K LOC
- 汇编生成: 3K LOC

### Day 20-26: SSA 规则库

**核心规则集** (13,000+ 条):

```s
// 文件: src/cmd/compile/internal/backend/ssa_rules.s

package backend

// 算术优化规则 (1,000 条)
// 规则格式: (opcode, operand_patterns) -> (result_opcode, result_operands)

const RULE_CONST_FOLD_INT_ADD = 1000
const RULE_CONST_FOLD_INT_MUL = 1001
const RULE_IDENTITY_ADD_ZERO = 2000
const RULE_IDENTITY_MUL_ONE = 2001
const RULE_MUL_BY_POWER_OF_TWO = 2002    // x * 2^n → x << n
const RULE_ASSOC_ADD = 3000              // (a+b)+c → a+(b+c)

// x86-64 寻址模式规则 (500 条)
const RULE_ADDR_BASE_SCALE = 10000       // a + (b * 4)
const RULE_ADDR_BASE_SCALE_OFFSET = 10001
const RULE_ADDR_BASE_SCALE_DISP = 10002

// x86-64 特定规则 (2,500+ 条)
const RULE_AMD64_LEA = 20000             // Load Effective Address
const RULE_AMD64_IMUL_COMB = 20001       // 融合 mul + add
const RULE_AMD64_DIV_BY_CONST = 20002    // 常数除法优化

// ARM64 特定规则 (2,200+ 条)
const RULE_ARM64_CSEL = 30000            // Conditional Select
const RULE_ARM64_SHIFT_COMBINE = 30001

// ... 更多架构

struct ssa_rule {
    rule_id: int
    pattern: ir_instruction
    cost: int
    result: ir_instruction
    applicable_archs: int[]
}

func match_ssa_rule(instr: &ir_instruction, rules: &ssa_rule[]) ssa_rule {
    // 尝试匹配规则
    // 返回成本最低的规则
}

// 规则集加载与管理
func init_ssa_rules(target_arch: int) ssa_rule[] {
    // 加载目标架构的规则
}

func apply_ssa_rules(ir: &ir_instruction[], rules: &ssa_rule[]) x86_64_instr[] {
    // 应用规则进行指令选择
}
```

**规则库分布**:
- 常用算术 (1,000): 常数折叠、化简、结合律
- 寻址模式 (500): 各种寻址方式
- x86-64 (2,500): LEA、IMUL、DIV、位操作
- ARM64 (2,200): CSEL、位移、内存操作
- RISC-V (1,500): 压缩指令、特殊操作
- 其他 (3,800): 更多架构

**子任务**:
- [ ] 规则编码格式设计
- [ ] 规则匹配引擎
- [ ] 算术优化规则 (1,000 条)
- [ ] 寻址规则 (500 条)
- [ ] x86-64 规则 (2,500+ 条)
- [ ] ARM64 规则 (2,200+ 条)
- [ ] 规则测试 (1000+ 个)

**验证**: `make ssa-rules-test` 通过

---

### Day 27-29: 寄存器分配 (Register Allocation)

```s
// 文件: src/cmd/compile/internal/backend/regalloc.s

package backend

struct live_range {
    var_id: int
    start: int          // 指令索引
    end: int
    registers: int[]    // 可用寄存器
}

struct interference_graph {
    nodes: int          // 变量数
    edges: bool[][]     // 干涉矩阵
    colors: int[]       // 颜色分配
}

struct register_allocator {
    function: ir_function
    live_ranges: live_range[]
    interference: interference_graph
    spill_cost: float[]
    allocated: int[]    // var_id → reg_id
}

// x86-64 寄存器
const REG_RAX = 0
const REG_RBX = 1
const REG_RCX = 2
// ... 16 个通用寄存器

const NUM_REGS = 16
const NUM_CALLEE_SAVED = 8

func build_live_ranges(func: &ir_function) live_range[] {
    // 从生存性信息构建活跃范围
}

func build_interference_graph(ranges: &live_range[]) interference_graph {
    // 两个范围重叠且变量互不相同 → 干涉
}

func allocate_registers(alloc: &mut register_allocator) {
    // 1. 按活跃范围排序
    // 2. 图着色算法
    // 3. 溢出处理
    // 4. 重新着色
}

func select_spill_candidate(graph: &interference_graph) int {
    // 选择溢出到栈的变量
    // 启发式：选择成本最低的
}

func emit_spill_code(func: &ir_function, var_id: int, stack_pos: int) {
    // 生成 spill 和 reload 指令
}
```

**子任务**:
- [ ] 活跃范围计算
- [ ] 干涉图构建
- [ ] 图着色实现
- [ ] 溢出处理
- [ ] 栈位置分配
- [ ] 单元测试 (500+ 个)

**验证**: `make regalloc-test` 通过

---

### Day 30-31: 代码生成与汇编 (Codegen & Asm)

```s
// 文件: src/cmd/compile/internal/backend/codegen.s

package backend

struct x86_64_instr {
    opcode: int         // MOV, ADD, JMP, ...
    operands: operand[]
    line: int
}

struct operand {
    op_type: int        // REG, MEM, IMM, LABEL
    value: (int | string)
}

struct assembler {
    instructions: x86_64_instr[]
    labels: map[string, int]
    data_section: string[]
    rodata_section: string[]
}

func generate_code(ir: &ir_function, alloc: &register_allocator) x86_64_instr[] {
    // 遍历优化后的 IR
    // 应用 SSA 规则
    // 生成 x86-64 指令
}

func emit_function_prologue(frame_size: int) x86_64_instr[] {
    // push rbp
    // mov rbp, rsp
    // sub rsp, frame_size (如需)
}

func emit_function_epilogue() x86_64_instr[] {
    // pop rbp
    // ret
}

func assemble_to_asm(instrs: &x86_64_instr[]) string {
    // 生成 GNU 汇编代码
    // .globl main
    // main:
    //     mov $0, %rax
    //     ret
}
```

**子任务**:
- [ ] 指令模式设计
- [ ] IR → x86-64 转换
- [ ] Prologue/Epilogue 生成
- [ ] 标签和跳转处理
- [ ] 汇编格式输出
- [ ] 单元测试 (500+ 个)

**验证**: `make codegen-test` 通过

---

### 阶段 3 交付物检查清单

```
后端模块 (src/cmd/compile/internal/backend/)
├─ ✅ ssa_rules.s .................. 15K LOC (13,000+ 规则)
├─ ✅ regalloc.s ................... 5K LOC
├─ ✅ codegen.s .................... 5K LOC
├─ ✅ instr_select.s .............. 3K LOC
└─ ✅ 单元测试 (test/) ............ 5K LOC

总代码量: 28K LOC
单元测试: 2000+ 个
验证: ✅ make backend-test

里程碑: M3 ✅ 代码生成
```

---

## 阶段 4: 链接器 & 运行时 (Week 9-10)

### 目标
- 纯 S ELF 链接器
- 最小运行时
- 完整工具链

### 代码规模
- 总计：20K LOC
- 链接器: 12K LOC
- 运行时: 5K LOC
- 工具: 3K LOC

### Day 32-36: ELF 链接器

```s
// 文件: src/cmd/compile/internal/linker/linker.s

package linker

struct elf_header {
    magic: int          // 0x7F 'E' 'L' 'F'
    ei_class: int       // 1=32bit, 2=64bit
    ei_data: int        // 1=little, 2=big
    ei_version: int
    ei_osabi: int
    // ... 更多字段
}

struct elf_section_header {
    name_offset: int
    section_type: int   // SHT_PROGBITS, SHT_SYMTAB, ...
    flags: int          // SHF_WRITE, SHF_ALLOC, ...
    address: int
    offset: int
    size: int
    link: int
    info: int
    align: int
    entry_size: int
}

struct symbol_entry {
    name_offset: int
    value: int
    size: int
    binding: int        // STB_LOCAL, STB_GLOBAL, ...
    sym_type: int       // STT_NOTYPE, STT_OBJECT, STT_FUNC, ...
    visibility: int
    section_index: int
}

struct relocation {
    offset: int
    info: int           // (symbol_index << 32) | type
    addend: int
}

struct object_file {
    filename: string
    header: elf_header
    sections: elf_section_header[]
    symbols: symbol_entry[]
    relocations: relocation[][]  // 按 section 索引
    content: string[]
}

struct linker {
    input_files: object_file[]
    output_file: string
    symbol_table: symbol_entry[]
    section_offsets: int[]
    relocations_pending: relocation[]
}

func link(object_files: &string[], output: string) int {
    // 1. 读取所有目标文件
    // 2. 构建全局符号表
    // 3. 合并 sections
    // 4. 应用重定位
    // 5. 生成可执行文件
}

func read_object_file(filename: string) object_file {
    // 解析 ELF 格式
    // 提取 sections, symbols, relocations
}

func merge_sections(files: &object_file[]) merged_section[] {
    // 合并相同类型的 sections
    // 计算新的地址偏移
}

func resolve_symbols(files: &object_file[]) symbol_table {
    // 构建符号表
    // 检测未定义的符号
    // 检测符号冲突
}

func apply_relocations(sections: &merged_section[], symbols: &symbol_table) {
    // 对每个重定位记录：
    // value = symbol_value + reloc_addend
    // 写入目标地址
}

func write_elf(output: string, sections: &merged_section[], symbols: &symbol_table) {
    // 写入 ELF 文件
    // 包括：header, sections, symbol table, string table
}
```

**子任务**:
- [ ] ELF 格式解析
- [ ] 目标文件读取
- [ ] 符号表管理
- [ ] 符号解析
- [ ] 重定位处理
- [ ] ELF 文件生成
- [ ] 单元测试 (500+ 个)

**验证**: `make linker-test` 通过

---

### Day 37-39: 运行时与系统库

```s
// 文件: src/std/runtime_minimal.s

package std

// 系统调用编号 (x86-64 Linux)
const SYSCALL_WRITE = 1
const SYSCALL_READ = 0
const SYSCALL_OPEN = 2
const SYSCALL_CLOSE = 3
const SYSCALL_MMAP = 9
const SYSCALL_MUNMAP = 11
const SYSCALL_BRK = 12
const SYSCALL_EXIT = 60

// 内存分配器
struct heap_allocator {
    heap_start: int
    heap_end: int
    free_blocks: free_block[]
}

struct free_block {
    address: int
    size: int
    next: &free_block
}

func malloc(size: int) int {
    // 1. 找到足够大的空闲块
    // 2. 分裂块（如需）
    // 3. 返回地址
    // 4. 扩展 heap（如需）
}

func free(ptr: int) {
    // 1. 标记块为空闲
    // 2. 合并相邻空闲块
}

// 系统调用包装
func sys_write(fd: int, buf: &string, count: int) int {
    // syscall(SYSCALL_WRITE, fd, buf, count)
}

func sys_read(fd: int, buf: &string, count: int) int {
    // syscall(SYSCALL_READ, fd, buf, count)
}

func sys_exit(code: int) {
    // syscall(SYSCALL_EXIT, code)
}

// 启动代码（汇编）
// _start:
//     pop rdi            # argc
//     mov rsi, rsp       # argv
//     call main
//     mov rdi, rax       # 返回值作为 exit code
//     call sys_exit
```

**子任务**:
- [ ] 堆分配器实现
- [ ] 系统调用包装
- [ ] 启动代码
- [ ] I/O 操作
- [ ] 进程控制
- [ ] 单元测试 (300+ 个)

**验证**: `make runtime-test` 通过

---

### Day 40: 工具链完善

```s
// 文件: src/cmd/tools.s

// 工具：
// - s dump <file.o>      显示目标文件内容
// - s disasm <binary>    反汇编
// - s link <objects...>  链接器
// - s build <file.s>    完整编译
```

**子任务**:
- [ ] 目标文件转储工具
- [ ] 反汇编器
- [ ] 构建脚本
- [ ] 单元测试 (100+ 个)

**验证**: `make tools-test` 通过

---

### 阶段 4 交付物检查清单

```
链接器模块 (src/cmd/compile/internal/linker/)
├─ ✅ linker.s ....................... 12K LOC

运行时模块 (src/std/)
├─ ✅ runtime_minimal.s .............. 5K LOC

工具模块 (src/cmd/)
├─ ✅ tools.s ........................ 3K LOC

└─ ✅ 单元测试 (test/) ............ 4K LOC

总代码量: 20K LOC
单元测试: 900+ 个
验证: ✅ make linker-test
      ✅ make runtime-test

里程碑: M4 ✅ 链接器 & 运行时
```

---

## 阶段 5-7 简明版本

### 阶段 5: Stage 2 自编译 (Week 11-12)

**目标**: 完整编译器的第一个工作版本

```
make stage2-check:
    1. C seed 编译器 → 生成 stage1.s (前端)
    2. stage1.s 编译 → stage2 (完整编译器)
    3. stage2 编译自身 → stage3
    4. 验证: stage2 == stage3 (功能等价)
```

**交付物**: 可以独立编译 S 代码的二进制编译器

---

### 阶段 6: 真正自举 (Week 13-15)

**目标**: 消除 C 依赖，实现纯 S 自举

```
make true-selfhost-check:
    1. 删除 C seed 依赖
    2. stage2 完全用 S 编写
    3. 自编译验证
    4. 二进制对等测试
```

**交付物**: 完全独立的 S 编译器

---

### 阶段 7: 生产优化 (Week 16-18)

**目标**: 性能达成 100-500× 倍数提升

```
优化包括:
1. 追加 3,000+ SSA 规则
2. 工具链完善
3. 文档与示例
4. 性能基准测试
```

**交付物**: 生产级 S 编译器

---

## 总体 Makefile 目标

```makefile
# 阶段检查
make frontend-test          # 阶段 1
make middleend-test         # 阶段 2
make backend-test           # 阶段 3
make linker-test            # 阶段 4
make runtime-test           # 阶段 4

# 集成检查
make stage1-check           # 阶段 1: 前端自编译
make stage2-check           # 阶段 5: Stage 2 完整编译器
make true-selfhost-check    # 阶段 6: 纯 S 自举

# 完整验证
make all-tests              # 所有单元测试
make integration-tests      # 集成测试
make regression-tests       # 回归测试
make bootstrap-verify       # 自举验证
make benchmark              # 性能基准
```

---

## 资源分配

### 开发人员配置 (理想情况)

```
团队规模: 6-8 人

╔════════════════════════════════════╗
║ 架构设计 (1人)                     ║
║ 负责总体架构和设计决策             ║
╠════════════════════════════════════╣
║ 前端团队 (2人)                     ║
║ - Lexer/Parser/Semantic            ║
║ - 阶段 1 (Week 1-3)                ║
╠════════════════════════════════════╣
║ 中后端团队 (2人)                   ║
║ - IR/优化/代码生成                 ║
║ - 阶段 2-3 (Week 4-8)              ║
╠════════════════════════════════════╣
║ 运行时/链接器团队 (1人)            ║
║ - 链接器/运行时/系统库             ║
║ - 阶段 4 (Week 9-10)               ║
╠════════════════════════════════════╣
║ 测试与 QA (1人)                    ║
║ - 测试框架/自动化测试              ║
║ - 回归测试/性能基准                ║
╠════════════════════════════════════╣
║ 文档与工具 (1人)                   ║
║ - 文档/工具链/示例                 ║
║ - 发布管理                         ║
╚════════════════════════════════════╝
```

### 时间线甘特图

```
Week 1-3    ████████░░░░░░░░░░░░░░░░░ 前端
Week 4-5    ░░░░░░████░░░░░░░░░░░░░░░ 中间层
Week 6-8    ░░░░░░░░░████████░░░░░░░░ 后端
Week 9-10   ░░░░░░░░░░░░░░░░░████░░░░ 链接器/运行时
Week 11-12  ░░░░░░░░░░░░░░░░░░░░████░ Stage 2 自编译
Week 13-15  ░░░░░░░░░░░░░░░░░░░░░░░░ 纯 S 自举
Week 16-18  ░░░░░░░░░░░░░░░░░░░░░░░░ 优化与发布
```

---

## 风险管理

### 主要风险

| 风险 | 概率 | 影响 | 缓解策略 |
|------|------|------|---------|
| SSA 规则不完整 | 高 | 生成的代码不正确 | 逐步添加规则，频繁测试 |
| 自举环导致无穷循环 | 中 | 无法完成自举 | 保持 C seed，分阶段验证 |
| 性能目标失败 | 中 | 无法满足生产要求 | 性能基准驱动开发 |
| 链接器复杂度过高 | 低 | 无法完成 | 考虑使用 GNU ld 作为第一阶段 |

### 里程碑验收标准

```
M1 ✅ 完整前端
   ├─ 编译器前端自编译通过
   ├─ 1000+ Lexer 单元测试通过
   ├─ 2000+ Parser 单元测试通过
   └─ 2000+ Semantic 单元测试通过

M2 ✅ 中间层优化
   ├─ 1000+ IR Builder 测试
   ├─ 1000+ 分析测试
   └─ 1000+ 优化测试

M3 ✅ 代码生成
   ├─ 1000+ SSA 规则测试
   ├─ 500+ 寄存器分配测试
   └─ 生成的代码能运行小程序

M4 ✅ 链接器 & 运行时
   ├─ 500+ 链接器测试
   ├─ 300+ 运行时测试
   └─ 完整程序能独立运行

M5 ✅ Stage 2 自编译
   ├─ make stage2-check 通过
   ├─ Stage 2 能编译自身
   └─ 功能等价验证

M6 ✅ 真正自举
   ├─ make true-selfhost-check 通过
   ├─ 无 C 依赖符号
   └─ 二进制对等

M7 ✅ 生产发布
   ├─ 性能达成 100-500× 提升
   ├─ 所有测试通过
   └─ 文档完整
```

---

## 成功指标

### 功能指标
- ✅ 支持完整 S 语言语法
- ✅ 生成可执行的二进制代码
- ✅ 完全自举（无 C 依赖）
- ✅ 自编译验证通过

### 质量指标
- ✅ 代码覆盖率 > 80%
- ✅ 所有单元测试通过 (10,000+ 个)
- ✅ 回归测试通过
- ✅ 无内存泄漏

### 性能指标
- ✅ 编译速度提升 100-500×
- ✅ 生成代码质量达成 0.5-1.0× vs Go
- ✅ 自举时间 < 60 秒
- ✅ 编译器二进制 < 10MB

---

**下一步**: 实现阶段 1 前端组件
