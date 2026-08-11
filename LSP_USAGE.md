# S 语言 LSP 服务器使用指南

## 概述

LSP (Language Server Protocol) 为 S 语言提供编辑器支持。

**位置**: `/src/cmd/lsp/`

**核心模块**:
- `server.s` - LSP 服务器主程序
- `lsp_handler.s` - LSP 请求处理逻辑
- `lsp_protocol.s` - LSP 协议数据结构
- `jsonrpc.s` - JSON-RPC 2.0 通信
- `document_manager.s` - 文件和 AST 管理
- `build.sh` - 编译脚本

---

## 快速开始 (3 步)

### 1. 编译

```bash
cd /Users/shuwen/shuwen/s/src/cmd/lsp
bash build.sh
```

输出: `../../bin/s_lsp`

### 2. 启动

```bash
./bin/s_lsp
```

### 3. VS Code 配置

编辑 `.vscode/settings.json`:

```json
{
  "s.lsp.serverPath": "/Users/shuwen/shuwen/s/bin/s_lsp"
}
```

---

## 支持的功能

| 功能 | 方法 | 快捷键 |
|------|------|--------|
| 代码补全 | textDocument/completion | Ctrl+Space |
| 悬停提示 | textDocument/hover | 悬停即可 |
| 转到定义 | textDocument/definition | Ctrl+Click |
| 查找引用 | textDocument/references | Shift+F12 |
| 文档符号 | textDocument/documentSymbol | Ctrl+O |
| 重命名 | textDocument/rename | F2 |
| 诊断 | textDocument/publishDiagnostics | 实时显示 |

---

## JSON-RPC 通信

### 打开文件

```json
{
  "jsonrpc": "2.0",
  "method": "textDocument/didOpen",
  "params": {
    "textDocument": {
      "uri": "file:///path/test.s",
      "languageId": "s",
      "version": 1,
      "text": "package main\n\nfunc main() {}\n"
    }
  }
}
```

### 请求补全

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "textDocument/completion",
  "params": {
    "textDocument": { "uri": "file:///path/test.s" },
    "position": { "line": 3, "character": 6 }
  }
}
```

---

## 架构

```
VS Code (Client)
    ↓ JSON-RPC over stdin/stdout
LSP Server
    ↓
lsp_handler (请求分派)
    ↓
document_manager (文件管理)
    ↓
S 编译器前端 (lexer/parser)
    ↓
结果返回 → JSON-RPC 响应 → VS Code
```

---

## 核心数据结构

### jsonrpc_request

```s
struct jsonrpc_request {
    string jsonrpc
    string method
    option[map] params
    option[int] id
}
```

### text_document

```s
struct text_document {
    string uri
    string language_id
    int version
    string text
}
```

### diagnostic

```s
struct diagnostic {
    range r
    string message
    option[int] severity
    option[string] code
    option[string] source
}
```

---

## 文件事件

| 事件 | 说明 |
|------|------|
| textDocument/didOpen | 打开文件 |
| textDocument/didChange | 编辑文件 |
| textDocument/didSave | 保存文件 |
| textDocument/didClose | 关闭文件 |

---

## 调试

### 启用日志

修改 `server.s`:

```s
func (server mut lsp_server) handle_message(message string) {
    std::println("DEBUG: " + message)
    // ...
}
```

### 手动测试

```bash
./bin/s_lsp
# 发送 JSON-RPC 请求到 stdin
```

---

## 相关文件

| 文件 | 行数 | 功能 |
|------|------|------|
| server.s | 150+ | 主程序 |
| lsp_handler.s | 300+ | 请求处理 |
| lsp_protocol.s | 200+ | 数据结构 |
| jsonrpc.s | 150+ | JSON-RPC |
| document_manager.s | 250+ | 文件管理 |
| build.sh | 80+ | 编译 |

---

## 下一步

- 编译: `cd src/cmd/lsp && bash build.sh`
- 启动: `./bin/s_lsp`
- 配置 VS Code 扩展
- 享受智能编码体验！
