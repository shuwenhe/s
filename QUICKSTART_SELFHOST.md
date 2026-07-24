# S 编译器自举 - 快速参考

## 🎯 当前状态

**问题**：`./bin/s` 仍然链接到 C 库  
**根本原因**：Bootstrap 过程使用 C seed 编译器  
**解决方案**：已准备完整基础设施，等待集成

## 📁 已创建的文件

```
s/
├── src/std/runtime_nostdlib.s              最小化运行时
├── src/cmd/compile/selfhost/bootstrap_pure_s.s  纯S Bootstrap
├── linker_nostdlib.ld                      链接脚本
├── docs/SELFHOST_IMPLEMENTATION.md         详细指南
├── SELFHOST_ROADMAP.md                     行动计划
└── IMPLEMENTATION_SUMMARY.md               完成总结
```

## 🚀 立即可以做的事

### 1. 阅读文档（5分钟）
```bash
cd /home/shuwen/shuwen/s
cat SELFHOST_ROADMAP.md          # 行动计划
cat docs/SELFHOST_IMPLEMENTATION.md  # 技术细节
```

### 2. 验证基础设施（2分钟）
```bash
make selfhost-nostdlib           # 应该输出 "Infrastructure ready"
ls -la src/std/runtime_nostdlib.s
file linker_nostdlib.ld
```

### 3. 检查编译器状态（1分钟）
```bash
nm ./bin/s | grep seed_compile   # 显示 C 依赖
ldd ./bin/s | grep libc          # 显示 libc 依赖
```

## 📋 下一步实现清单

### Phase 1: 编译器链接独立化 (1-2 周)

**任务**：消除编译器的 C 库依赖

关键步骤：
1. [ ] 在编译器中实现 `extern "intrinsic" func syscall(...)` 支持
2. [ ] 修改 C seed 编译器的链接过程
3. [ ] 使用 `-nostdlib` 标志编译
4. [ ] 验证：`ldd ./bin/s_nostdlib` 无输出

关键文件：
- `src/cmd/compile/seed/code/native_backend.c` - IR→Binary 链接
- `Makefile` - 编译标志

### Phase 2: 纯 S 编译前端 (2-4 周)

**任务**：用 S 实现完整的编译器前端

关键组件：
- [ ] `src/cmd/compile/selfhost/parser.s` - 语法分析
- [ ] `src/cmd/compile/selfhost/semantic.s` - 语义检查
- [ ] `src/cmd/compile/selfhost/compile_pipeline.s` - 完整流程

### Phase 3: 完全自主引导 (4-8 周)

**任务**：100% S 实现，无需任何外部编译器

验证：
- [ ] `make true-selfhost-check` 通过
- [ ] 编译器不包含任何 C 符号
- [ ] 可以编译自身

## 🔧 技术细节速查

### Syscall 示例

```s
// 从 runtime_nostdlib.s
extern "intrinsic" func __syscall(int nr, int a1, int a2, int a3, int a4, int a5, int a6) int

// x86-64 Linux syscall 编号
const SYS_EXIT = 60
const SYS_WRITE = 1
const SYS_READ = 0
const SYS_OPEN = 2
const SYS_CLOSE = 3
const SYS_BRK = 12

// 使用示例
func exit(int code) {
    __syscall(SYS_EXIT, code, 0, 0, 0, 0, 0)
}
```

### 内存分配

```s
var heap_ptr: i64 = 0x10000000

func malloc(int size) &byte {
    let ptr = heap_ptr
    heap_ptr += i64(size)
    return &byte(ptr)
}
```

### 文件输出

```s
func stderr_write(string text) int {
    return write_fd(STDERR_FILENO, []byte(text))
}

func write_fd(int fd, []byte buffer) int {
    if len(buffer) == 0 { return 0 }
    return __syscall(SYS_WRITE, fd, 0, len(buffer), 0, 0, 0)
}
```

## 📊 进度表

| 任务 | 状态 | 文件 |
|------|------|------|
| 基础设施 | ✅ 完成 | 6 files, 1271 lines |
| 文档 | ✅ 完成 | 3 docs |
| Syscall 支持 | ⏳ 待做 | compiler |
| 链接独立化 | ⏳ 待做 | bootstrap |
| 编译前端 | ⏳ 待做 | parser.s |

## 🎓 关键代码位置

```
编译器架构：
┌─────────────────────────────────────┐
│ S 源代码 (main.s)                   │
└────────────┬────────────────────────┘
             ↓ (C seed 编译)
┌──────────────────────────────────────────┐
│ IR 中间表示 (stage1.ir, stage2.ir)      │
└────────────┬─────────────────────────────┘
             ↓ (emit-bin: IR→Binary)
┌──────────────────────────────────────────┐
│ 二进制可执行文件 (stage1, stage2)        │
│ ❌ 链接到 libc                           │
└──────────────────────────────────────────┘

目标架构：
┌─────────────────────────────────────┐
│ S 源代码                            │
└────────────┬────────────────────────┘
             ↓ (纯 S 编译)
┌──────────────────────────────────────────┐
│ IR 中间表示                             │
└────────────┬─────────────────────────────┘
             ↓ (纯 S: IR→ASM→Binary)
┌──────────────────────────────────────────┐
│ 二进制可执行文件                         │
│ ✅ 完全独立，无依赖                      │
└──────────────────────────────────────────┘
```

## 💻 命令速查

```bash
# 查看编译器依赖
nm ./bin/s | grep -E "seed_|__libc"
ldd ./bin/s

# 构建新目标
make selfhost-nostdlib

# 测试编译能力
echo 'func main() int { return 42 }' > test.s
./bin/s test.s /tmp/test.ir

# 验证进度
make true-selfhost-check  # 应该失败（预期）
```

## 📚 完整文档

- **SELFHOST_ROADMAP.md** - 详细的三阶段计划
- **docs/SELFHOST_IMPLEMENTATION.md** - 技术实现指南
- **IMPLEMENTATION_SUMMARY.md** - 工作总结

## ✨ 预期最终状态

完成后的编译器：
- ✅ 用 S 编写
- ✅ 可以编译 S 代码
- ✅ 可以编译自身
- ✅ 无需任何 C 库
- ✅ 真正实现自举

## 🤝 贡献方式

1. **选择一个里程碑**（参考 SELFHOST_ROADMAP.md）
2. **按照行动计划**实现相应功能
3. **运行验证命令**确保进度
4. **提交 Pull Request** 并说明完成的里程碑

---

**Last Updated**: 2026-07-24  
**Current Commit**: c8b6d274  
**Status**: 🟡 基础设施就位，等待集成

需要帮助？查看 SELFHOST_ROADMAP.md "立即行动" 部分！
