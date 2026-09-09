# Windows平台支持

## 概述

Windows平台支持规划（待实现）。

## 目标

### 架构
- 🟡 x86_64 (amd64)
- ❌ ARM64 (不在计划中)

### 功能
- 🟡 静态链接
- 🟡 动态链接 (.dll)
- 🟡 导入库 (.lib)
- 🟡 清单 (.manifest)
- 🟡 资源 (.rc)

## 实现计划

### 阶段1: 基础支持 (2025年10月)
- [ ] PE二进制格式定义
- [ ] 基础汇编生成
- [ ] 编译器集成 (cl.exe)

### 阶段2: 功能完善 (2025年11月)
- [ ] 动态链接库支持
- [ ] 导入库生成
- [ ] 代码签名

### 阶段3: 优化 (2025年12月+)
- [ ] 调试符号 (PDB)
- [ ] 优化配置
- [ ] 工具链集成

## 开发信息

### 二进制格式
```
DOS MZ头 (兼容性)
  ↓
PE签名 (0x50 0x45 "PE")
  ↓
COFF文件头
  - CPU类型: 0x8664 (x86_64)
  - 节数量
  - 时间戳
  ↓
可选头
  - 入口点
  - 基址
  - 节对齐
  ↓
节表
  - .text (代码)
  - .data (初始化数据)
  - .rdata (只读数据)
  - .reloc (重定位)
```

### 调用约定
- 参数寄存器: rcx, rdx, r8, r9
- 返回值: rax, rdx
- 被调用者保存: rbx, rbp, rdi, rsi, r12-r15

## 参考资源

- [PE文件格式规范](https://docs.microsoft.com/en-us/windows/win32/debug/pe-format)
- [x86_64微软ABI](https://docs.microsoft.com/en-us/cpp/build/x64-software-conventions)
- [MSVC工具链](https://docs.microsoft.com/en-us/cpp/)

## 相关

参考: [PLATFORM_ARCHITECTURE.md](../PLATFORM_ARCHITECTURE.md)
