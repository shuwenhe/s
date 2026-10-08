# compile 目录结构优化分析

## 📊 当前规模

| 指标 | 数值 |
|------|------|
| 总文件数 | 1577 .s 文件 |
| 总目录数 | 90 个 |
| 深度 | 3-4 级 |

### 主要模块分布

```
backend/    679 文件  (43%)  → 代码生成与后端优化
middlend/   390 文件  (25%)  → 中端处理与 IR
frontend/   309 文件  (20%)  → 前端解析与分析  
internal/   176 文件  (11%)  → 内部基础设施
其他/         23 文件  (1%)   → bootstrap, seed, testing, platforms
```

---

## 🔍 发现的问题

### 1. 后端模块命名混乱 (backend/)
```
backend/
├── backend/           ⚠️ 重复命名 (backend/backend)
├── obj/               ⚠️ 不清晰 (目的？)
├── objw/              ⚠️ 不清晰 (obj + w?)
├── object/            ⚠️ 与 obj 重复？
├── codegen/           ✅ 清晰
├── target/            ✅ 清晰
├── abi/               ✅ 清晰
├── build/             ✅ 清晰
├── tools/             ✅ 清晰
├── internal/          ⚠️ 通用名字
└── selfhost/          ⚠️ 应合并
```

**问题分析**:
- `backend/backend/` - 名称冗余，应改为更具体的功能名
- `obj/`, `objw/`, `object/` - 功能不明确，应统一为 `objects/` 或更清晰的名称
- 10+ 个子目录，结构复杂

### 2. 前端模块层级深 (frontend/)
```
frontend/
├── types/       （核心类型系统）
├── types2/      ⚠️ 与 types 什么关系？
├── parser/      ✅ 清晰
├── lexer/       ✅ 清晰
├── scanner/     ⚠️ 与 lexer 重复？
├── printer/     ✅ 清晰
├── noder/       ❓ 含义不清
├── ast/         ✅ 清晰
├── semantic/    ✅ 清晰
├── typecheck/   ⚠️ 与 check 重复？
├── check/       ⚠️ 与 typecheck 重复？
├── resolve/     ✅ 清晰
├── format/      ✅ 清晰
└── ... 其他
```

**问题分析**:
- 19 个子目录，过于细化
- `types/` 和 `types2/` - 版本不清楚
- `scanner/` 和 `lexer/` - 功能重复？
- `check/` 和 `typecheck/` - 关系不明
- `frontend_internal/` - 通用名字

### 3. 中端模块结构复杂 (middlend/)
```
middlend/
├── ir/          ✅ 清晰 (中间表示)
├── ssa/         ✅ 清晰 (静态单赋值)
├── ssagen/      ⚠️ ssa 相关？应在 ssa/ 下
├── mir/         ✅ 清晰 (机器 IR)
├── inline/      ✅ 清晰 (内联优化)
├── walk/        ❓ 含义不清 (遍历？)
├── bounds/      ✅ 清晰 (边界检查)
├── liveness/    ✅ 清晰 (活跃性分析)
├── deadlocals/  ✅ 清晰 (死局部变量)
├── devirtualize/✅ 清晰 (去虚拟化)
├── ownership/   ✅ 清晰 (所有权分析)
├── mono/        ❓ 含义不清 (单态化？)
├── loopvar/     ✅ 清晰 (循环变量)
├── middleend/   ⚠️ 与 middlend 重复
├── pgoir/       ❓ PGO IR?
└── ... 其他
```

**问题分析**:
- 19 个子目录，优化细节过度分散
- `ssagen/` 应在 `ssa/` 下
- `middleend/` 和 `middlend/` 命名冗余
- 缺乏逻辑分组（优化、分析、生成）

### 4. 内部模块不统一 (internal/)
```
internal/
├── base/        ✅ 清晰
├── bitvec/      ✅ 清晰
├── pipeline/    ✅ 清晰
├── compiler/    ✅ 清晰
├── test/        ⚠️ 与 tests 区别？
├── tests/       ⚠️ 与 test 重复
├── abt/         ❓ 含义不清
├── bloop/       ❓ 含义不清
└── ... 其他
```

**问题分析**:
- `test/` 和 `tests/` 命名混乱
- `abt/`, `bloop/` 等含义不清

### 5. 跨模块问题
```
frontend/selfhost/   ⚠️ Bootstrap 代码分散
middlend/selfhost/   ⚠️ 应统一到 bootstrap/
backend/selfhost/    ⚠️ 
bootstrap/           ✅ 已有统一目录，但代码分散
```

**问题分析**:
- selfhost 代码分散在 3 个地方
- 应统一到 `bootstrap/` 或 `internal/bootstrap/`

### 6. 测试代码分散
```
internal/test/       (某些测试)
internal/tests/      (某些测试)
frontend/*_test.s    (测试文件混在模块里)
middlend/*_test.s    (测试文件混在模块里)
backend/*_test.s     (测试文件混在模块里)
```

**问题分析**:
- 测试代码位置不统一
- 混在功能代码中
- 难以区分单元测试、集成测试

---

## ✨ 优化建议

### 方案 A: 渐进式优化（推荐）

#### 第 1 步：整理后端模块 (高优先级)
```
backend/
├── codegen/         (代码生成)
├── target/          (目标特定)
│   ├── amd64/
│   ├── arm64/
│   └── ...
├── abi/             (ABI 定义)
├── objects/         (改: obj, objw, object 统一)
│   ├── elf.s
│   ├── macho.s
│   └── ...
├── linker/          (改: build → linker 更清晰)
├── tools/           (辅助工具)
└── internal/        (内部实现)
```

**变更**:
- `backend/backend/` → 删除或合并到 `backend/`
- `obj/`, `objw/`, `object/` → `backend/objects/`
- `build/` → `backend/linker/`

#### 第 2 步：简化前端模块 (中优先级)
```
frontend/
├── lexer/           (词法分析 - 统一 lexer + scanner)
├── parser/          (语法分析)
├── ast/             (抽象语法树)
├── semantic/        (语义分析)
├── types/           (类型系统 - types + types2 合并)
├── resolve/         (名称解析)
├── printer/         (输出格式化)
└── internal/        (内部工具)
```

**变更**:
- `scanner/` → 合并到 `lexer/`
- `types/` + `types2/` → 统一为 `types/`（版本控制处理）
- `typecheck/` + `check/` → 统一为 `semantic/check/`
- 删除 `frontend_internal/`，代码移到各模块

#### 第 3 步：重组中端优化 (中优先级)
```
middlend/
├── ir/              (中间表示)
│   ├── ir.s
│   ├── builder.s
│   └── ...
├── ssa/             (静态单赋值形式)
│   ├── ssa.s
│   ├── gen.s        (改: ssagen → gen)
│   └── ...
├── analysis/        (分析 - 新分组)
│   ├── liveness.s
│   ├── ownership.s
│   ├── bounds.s
│   └── ...
├── optimize/        (优化 - 新分组)
│   ├── inline.s
│   ├── devirtualize.s
│   ├── deadlocals.s
│   └── ...
└── walk.s           (通用遍历工具)
```

**变更**:
- `ssagen/` → `ssa/gen.s`
- `middleend/` → 删除（冗余）
- 创建 `analysis/` 分组（liveness, ownership, bounds）
- 创建 `optimize/` 分组（优化相关）
- `pgoir/`, `mono/`, `loopvar/` 等归入相应分组

#### 第 4 步：统一测试与 Bootstrap (低优先级)
```
compile/
├── ...（主要模块）
├── bootstrap/       (自举代码)
│   ├── frontend.s
│   ├── middlend.s
│   ├── backend.s
│   └── ...（从 frontend/selfhost 等迁移）
└── testing/         (测试基础设施)
    ├── unit/        (单元测试)
    ├── integration/ (集成测试)
    └── golden/      (黄金测试)
```

**变更**:
- 合并 `frontend/selfhost/`, `middlend/selfhost/`, `backend/selfhost/` → `bootstrap/`
- 统一 `internal/test/` 和 `internal/tests/` → `testing/`
- 建立测试分类

---

### 方案 B: 激进式重构（风险较高）

完全重新组织为：
```
compile/
├── main.s
├── frontend/        (前端 - 简化)
├── middlend/        (中端 - 重新分组)
├── backend/         (后端 - 简化)
├── lib/             (共享库)
├── tools/           (辅助工具)
├── bootstrap/       (自举)
└── testing/         (测试)
```

**优点**: 结构最清晰
**缺点**: 工作量大，风险高，易产生破坏

---

## 📋 优化优先级

### 高优先级 (建议立即做)
1. ✅ 后端: `obj/`, `objw/`, `object/` → `objects/`（简单改名）
2. ✅ 后端: `backend/backend/` → 删除或合并（降低复杂度）
3. ✅ 前端: `scanner/` → 合并到 `lexer/`（逻辑合并）

### 中优先级 (可作为下一步)
4. 中端: 创建 `analysis/` 和 `optimize/` 分组
5. 前端: `types/` + `types2/` 合并规划
6. 统一 `test/` 和 `tests/` 目录

### 低优先级 (长期改进)
7. 合并 selfhost 代码到统一 `bootstrap/`
8. 建立测试子分类
9. 清理不清晰的命名（`abt/`, `bloop/` 等）

---

## 🎯 预期收益

### 优化后效果
- ✅ 目录深度减少: 4级 → 3级
- ✅ 子目录数减少: 90 → ~50-60
- ✅ 结构清晰度提升: 易于导航
- ✅ 新开发者上手更快
- ✅ 维护成本降低

### 风险控制
- 使用 git mv 保留历史
- 批量更新导入语句
- 逐步迁移（阶段性）
- 充分测试每个阶段

---

## 📝 实施路线图

### 第 1 阶段 (1-2 周): 后端优化
- [ ] 改名 `obj/` → `objects/`
- [ ] 删除 `backend/backend/` 或重命名
- [ ] 改名 `build/` → `linker/`
- [ ] 运行验证测试

### 第 2 阶段 (1-2 周): 前端优化
- [ ] 合并 `scanner/` 到 `lexer/`
- [ ] 计划 `types/` + `types2/` 合并
- [ ] 清理 `frontend_internal/`

### 第 3 阶段 (2-3 周): 中端重组
- [ ] 创建 `analysis/` 目录
- [ ] 创建 `optimize/` 目录
- [ ] 迁移优化相关文件

### 第 4 阶段 (1 周): 测试与 Bootstrap
- [ ] 统一 `test/` 和 `tests/`
- [ ] 合并 selfhost 代码
- [ ] 最终验证

---

## 相关文档

- Go 编译器目录结构: https://github.com/golang/go/tree/master/src/cmd/compile
- Rust 编译器结构: https://github.com/rust-lang/rust/tree/master/src

