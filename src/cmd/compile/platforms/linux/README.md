# Linux平台支持

## 概述

S编译器在Linux平台上的完整支持，包括ELF二进制生成。

## 支持

### 架构
- ✅ x86_64 (amd64)
- ✅ ARM64

### 功能
- ✅ 静态链接
- ✅ 动态链接 (.so)
- ✅ 位置独立代码 (PIE)
- 🟡 调试符号 (DWARF)
- 🟡 线程本地存储 (TLS)

## 实现

当前Linux后端由 `seed/code/standalone_amd64_backend.c` 实现。

### 主要文件
- `seed/code/standalone_amd64_backend.c` - x86_64代码生成
- `seed/code/native_backend.c` - C代码生成

## 使用

编译为Linux目标：
```bash
S_TARGET_OS=linux S_TARGET_ARCH=amd64 s build app.s -o app
```

## 性能

- 编译速度: ~50-100ms
- 二进制大小: 8-10KB (最小程序)

## 待实现

- [ ] Linux本地后端 (用S实现)
- [ ] ARM64后端完整优化
- [ ] 调试符号支持
- [ ] 线程本地存储支持

参考: [PLATFORM_ARCHITECTURE.md](../PLATFORM_ARCHITECTURE.md)
