# -nostdlib 编译支持实现计划

## 目标
实现编译器的 `-nostdlib` 选项，生成不依赖 C 库的可执行文件。

## 当前状态
- ✅ S 编译器源代码完整
- ✅ S 运行时框架存在 (src/std/runtime_nostdlib.s)
- ✅ Linker 脚本存在 (src/runtime/linker/nostdlib.ld)
- ❌ 编译器不支持 -nostdlib 选项
- ❌ 后端未集成静态链接配置
- ❌ 系统调用未完全实现

## 实现步骤

### 阶段 1：编译器选项支持 (1-2 小时)
**文件**: src/cmd/compile/internal/build/parse/parse.s

```
修改：
1. parse_options() - 解析 -nostdlib 标志
2. make_options() - 扩展选项结构体
3. usage() - 更新帮助信息

新语法：
  s build <path> -o <output> -nostdlib
  s run <path> -nostdlib
```

### 阶段 2：后端集成 (1-2 小时)
**文件**: 
- src/cmd/compile/internal/backend_elf64.s
- src/cmd/compile/internal/backend/backend.s

```
修改：
1. 接收 nostdlib 标志
2. 使用 src/runtime/linker/nostdlib.ld
3. 禁用 C 库链接标志
4. 设置静态链接 (-static)
```

### 阶段 3：S 运行时完善 (2-3 小时)
**文件**: src/std/runtime_nostdlib.s

```
实现：
1. 完整的系统调用包装
2. 堆管理 (malloc/free)
3. 程序启动 (_start)
4. 异常处理
5. I/O 操作

系统调用 (Linux x86_64)：
- SYS_exit (60)
- SYS_write (1)
- SYS_read (0)
- SYS_open (2)
- SYS_close (3)
- SYS_brk (12)
```

### 阶段 4：测试与验证 (1-2 小时)
```
测试用例：
1. 最小程序编译
2. 输出程序功能验证
3. 系统调用确认
4. 自举验证 (make true-selfhost-check)

验证命令：
  make build program.s -nostdlib
  readelf -hW program        # 检查无 INTERP
  nm -a program              # 检查无 libc 符号
  ./program                  # 功能测试
```

## 关键技术细节

### 链接脚本集成
```
使用: src/runtime/linker/nostdlib.ld
特点：
- ENTRY(_start) - 使用 S 定义的入口
- 禁用 .interp 和 .dynamic
- 静态段排列
```

### 系统调用方式
```
x86_64 Linux 系统调用约定：
rax = 系统调用号
rdi, rsi, rdx, r10, r8, r9 = 参数 1-6
syscall 指令 = 调用内核
```

### 编译器入口
```
原来：bin/s 依赖 libc main()
未来：bin/s 使用 S 定义的 _start

流程：
  S _start()
    ↓
  初始化 (栈、堆、args)
    ↓
  S main()
    ↓
  SYS_exit
```

## 风险和注意

| 风险 | 缓解 |
|------|------|
| 系统调用错误导致崩溃 | 充分测试每个系统调用 |
| 架构兼容性 | 初期只支持 x86_64，后扩展 ARM64 |
| 堆管理泄漏 | 简单的 bump allocator，监控使用 |
| 启动时间 | S 运行时开销最小化 |

## 完成后的收益

✅ bin/s 完全独立于 C 库
✅ 可以删除 C seed 编译器
✅ true-selfhost-check 通过
✅ 编译器真正自举
✅ 100% S 代码实现

## 时间估计

总计：**5-9 小时**
- 选项支持：1-2h
- 后端集成：1-2h
- 运行时：2-3h
- 测试：1-2h

## 下一步

执行顺序：
1. 实现阶段 1（编译器选项）
2. 实现阶段 2（后端集成）
3. 实现阶段 3（S 运行时）
4. 阶段 4（测试验证）
5. 删除 C seed（或存档）
