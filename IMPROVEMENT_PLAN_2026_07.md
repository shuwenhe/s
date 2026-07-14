# S 语言项目改进计划 (2026-07-14)

## 📊 当前项目状态

| 指标 | 状态 | 评分 |
|------|------|------|
| 整体完成度 | 60-70% | 🟡 |
| 代码规模 | 7,897 文件, 215K LOC | ⚠️ |
| 网络模块 | 50-60% | 🟡 快速改进中 |
| 运行时系统 | 70-80% | 🟡 基本可用 |
| 标准库 | 95%+ | 🟢 完整 |
| 测试覆盖 | 78% | 🟡 良好 |

---

## 🔴 优先级 1: 立即处理 (第 1-2 周)

### 1.1 Socket 系统调用层 [🟡 90% 完成]
**工作量**: 5-7 天 | **影响**: 极高 | **状态**: 🟡 最后阶段

**进度**:
- ✅ Phase 1 (1 天) 完成 - 架构设计
- ✅ Phase 2 (90%) - Linux x86_64 实现基本完成
  - ✅ 系统调用绑定 `syscall_linux_x86_64.s` (391 行) - 已添加 sendto/recvfrom
  - ✅ Socket 核心操作 `socket_core.s` (615 行) - 已添加 SendTo/RecvFrom
  - ✅ Socket 类型定义 `socket_types.s` (283 行)
  - ✅ TCP 高层 API (232 行)
  - ✅ UDP 高层 API `udpconn_new.s` (315 行) - 新增完整 UDP 支持
  - ✅ 单元和集成测试 `socket_test.s` (544 行) - 已添加 4 个集成测试
- ✅ Phase 2.1 (100%) - TCP 完整实现
- ✅ Phase 2.2 (100%) - UDP 完整实现
- ⏳ Phase 3 (需完成) - IP 地址解析
- ⏳ Phase 4 (待开始) - 网络轮询集成

**已消除的 TODO**: 4/8 个 (TCP/UDP 核心功能已通过新实现消除)

**关键文件**:
- `src/net/internal/socket_types.s` ✅ (283 行)
- `src/net/internal/syscall_linux_x86_64.s` ✅ (391 行) 
- `src/net/internal/socket_core.s` ✅ (615 行)
- `src/net/internal/tcpconn_new.s` ✅ (232 行)
- `src/net/internal/udpconn_new.s` ✅ (315 行) - 新增
- `src/net/internal/socket_test.s` ✅ (544 行)
- `SOCKET_SYSCALL_ARCHITECTURE.md` ✅ (设计文档)
- `SOCKET_IMPLEMENTATION_PROGRESS.md` ✅ (详细进度)
- `UDP_IMPLEMENTATION_COMPLETE.md` ✅ (UDP 完成报告) - 新增

---

### 1.2 TCP/UDP 超时机制 [✅ 已实现]
**工作量**: 2-3 天 | **影响**: 高 | **状态**: ✅ 完成

**实现内容**:
- ✅ `SetDeadline()`, `SetReadDeadline()`, `SetWriteDeadline()` 完整实现
- ✅ 基于纳秒精度的截止期限
- ✅ 自动 poll 超时计算
- ✅ 过期检测和立即返回
- ✅ 完整错误处理

**位置**: `src/net/internal/socket_core.s` 第 169-197 行

**验收标准**: ✅
- [x] TCPConn 支持所有 Deadline 操作
- [x] UDPConn 支持所有 Deadline 操作 (通过 RawSocket 继承)
- [x] 超时时返回正确的错误

---

### 1.3 网络模块单元和集成测试 [✅ 90% 完成]
**工作量**: 2-3 天 | **影响**: 中 | **状态**: ✅ 基本完成

**已实现** (11 个单元测试):
- ✅ TestSocketCreate() - socket 创建
- ✅ TestSocketCreateUDP() - UDP socket 创建  
- ✅ TestSocketClose() - socket 关闭
- ✅ TestSetReuseAddr() - SO_REUSEADDR 选项
- ✅ TestSetTCPNoDelay() - TCP_NODELAY 选项
- ✅ TestSetBufferSize() - 缓冲区大小
- ✅ TestHtons() - 字节序转换
- ✅ TestNtohs() - 反向字节序转换
- ✅ TestSocketError() - 错误处理
- ✅ TestIsTemporaryError() - 临时错误判断
- ✅ TestIsTimeoutError() - 超时错误判断

**已实现** (4 个集成测试):
- ✅ TestTCPServerClientIntegration() - 完整 TCP 通信
- ✅ TestUDPCommunication() - UDP 发送接收
- ✅ TestTimeoutHandling() - 超时场景
- ✅ TestConcurrentConnections() - 并发连接

**位置**: `src/net/internal/socket_test.s`

**测试覆盖**:
- TCP listen/connect/read/write ✅ (完整实现)
- UDP sendto/recvfrom ✅ (完整实现)
- 超时和错误条件 ✅ (已验证)
- 并发操作 ✅ (已验证)

---

## 🟡 优先级 2: 本周处理 (第 2-3 周)

### 2.1 运行时调度器优化
**工作量**: 1 天 | **影响**: 5-10% 性能提升 | **状态**: 🟡

**当前问题**:
```s
// src/runtime/proc.s line 182
// TODO: 高效的 dequeue — 当前简化为线性移位
```

**改进方案**:
- 将 goroutine 队列从数组改为链表或环形缓冲区
- 改进 O(n) → O(1) 的出队列性能
- 实现无锁队列 (lock-free queue)

**性能指标**:
- [ ] 调度延迟 < 1μs (当前: ~100ns baseline)
- [ ] 吞吐量 > 1M goroutines/sec

---

### 2.2 标准库 P0 完整性检查
**工作量**: 3-4 天 | **影响**: 高

**当前状态**:
- ✅ fmt, errors, strings, strconv, bytes - 完整
- ✅ io, os - 基本完整
- ⚠️ json, encoding - 部分实现
- 🔴 http, net - 依赖网络模块

**改进清单**:
```
P0 包完整性:
├─ fmt.s          [✅ 100%] Sprintf, Printf, Fprintf
├─ errors.s       [✅ 100%] New, Wrap, Unwrap
├─ strings.s      [✅ 100%] Split, Join, Contains, Replace
├─ strconv.s      [✅ 100%] Atoi, ParseInt, ParseFloat
├─ bytes.s        [✅ 100%] Buffer, Reader operations
├─ io.s           [✅ 95%]  Reader, Writer, Reader-Writer
├─ os.s           [🟡 85%] File ops, Stat (缺少高级功能)
├─ path.s         [🟡 90%] Join, Dir, Base (缺少 Glob)
├─ regexp.s       [🟡 70%] Match, FindAll (缺少编译缓存)
└─ json.s         [🟡 60%] Marshal, Unmarshal (缺少流处理)
```

**待办项目**:
- [ ] 完成 json.s 的流处理 API
- [ ] 添加 regexp 编译缓存
- [ ] 完成 os.s 的 Glob 和 Walk
- [ ] 添加 path/filepath 完整支持

---

### 2.3 HTTP 基础库 (用于推理服务器)
**工作量**: 4-5 天 | **影响**: 中高 | **依赖**: 网络模块完成

**当前问题**:
- `src/net/http/` 存在但不完整
- 缺少 HTTP/1.1 完整实现

**改进方案**:
1. 实现 HTTP/1.1 客户端和服务器
2. 支持常见的 HTTP 方法 (GET, POST, PUT, DELETE)
3. 支持 chunked transfer encoding
4. 支持 gzip 压缩

**验收标准**:
- [ ] 可以启动 HTTP 服务器并侦听
- [ ] 支持 JSON 响应 (与 json.s 集成)
- [ ] 支持 multipart/form-data 上传

---

## 🟢 优先级 3: 并行进行 (第 3-8 周)

### 3.1 自托管编译器
**工作量**: 10-15 天 | **优先级**: 低 | **建议**: 后续阶段

**目标**:
- 用 S 语言实现 S 编译器
- 消除对 C/Go 编译器的依赖
- 实现自托管引导

**里程碑**:
1. 实现 lexer (S写S)
2. 实现 parser
3. 实现 code generator
4. 验证自编译

---

### 3.2 跨平台支持增强
**工作量**: 5-10 天/架构 | **优先级**: 低

**当前支持**:
- ✅ Linux x86_64
- ✅ macOS ARM64 (部分)
- ❌ Windows
- ❌ Linux ARM64

**改进计划**:
- [ ] Windows x86_64 完全支持
- [ ] Linux ARM64 支持
- [ ] FreeBSD 支持
- [ ] WebAssembly 支持 (可选)

---

### 3.3 性能分析工具 (pprof)
**工作量**: 5-7 天 | **优先级**: 低 (可选)

**目标**:
- CPU profiling 支持
- Memory profiling 支持
- Goroutine profiling
- 块分析

---

## 📈 改进效果预测 (7 周后)

### 完成度提升

```
┌─────────────────┬────────┬────────┬─────────┐
│    模块          │ 当前   │ 目标   │ 改进    │
├─────────────────┼────────┼────────┼─────────┤
│ 网络模块         │  30%   │  85%   │ +55%    │
│ 运行时系统       │  70%   │  85%   │ +15%    │
│ 标准库           │  95%   │  98%   │ +3%     │
│ 测试覆盖         │  78%   │  85%   │ +7%     │
│ 整体项目         │  60%   │  78%   │ +18%    │
└─────────────────┴────────┴────────┴─────────┘
```

### 代码增长

- 新增代码: ~5-10K LOC
- 消除 Stub (关键路径): 63 → 20
- 消除 TODO (关键路径): 17 → 0
- 测试文件增加: +30-40 个

---

## 🎯 推荐行动计划

### Week 1-2: 基础设施
1. **Day 1-2**: 设计 socket syscall wrapper 架构
2. **Day 3-4**: 实现 Linux 绑定 (x86_64)
3. **Day 5-6**: 实现 macOS 绑定 (ARM64)
4. **Day 7**: 集成网络轮询
5. **Day 8-10**: 添加超时和测试

### Week 2-3: 完整性
1. 完成网络模块测试
2. 审查和完成标准库 P0
3. 修复已知的 17 个 TODO

### Week 3-8: 扩展
1. HTTP 库完整实现
2. 自托管编译器 (可选)
3. 跨平台支持
4. 性能分析

---

## 📋 检查清单

### 必需完成 ✅

- [ ] Socket 系统调用层实现 (所有平台)
- [ ] TCP/UDP 超时设置
- [ ] 网络模块 > 80% 测试覆盖
- [ ] 标准库 P0 > 90% 完整
- [ ] 所有关键路径的 TODO = 0

### 建议完成 🟡

- [ ] 调度器性能优化
- [ ] JSON 流处理 API
- [ ] HTTP/1.1 基础库
- [ ] 测试覆盖达 85%

### 可选完成 🟢

- [ ] 自托管编译器
- [ ] 完整跨平台支持
- [ ] 性能分析工具

---

## 📞 相关文档

- 原工业化计划: `doc/industrial_burndown_plan.md` (已过期 25 天)
- Stub 消除检查表: `doc/destub-checklist.md` (465 个 stub)
- 标准库优先级: `doc/stdlib_top20_plan.md`
- 详细结构分析: `doc/PROJECT_STRUCTURE_ANALYSIS_2026_07.md`

---

**最后更新**: 2026-07-14  
**预计完成**: 2026-08-25 (11 周)  
**项目负责**: S Language Team
