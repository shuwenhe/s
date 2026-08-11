#!/bin/bash
# S Language LSP Server 编译脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/../.."
LSP_DIR="$SCRIPT_DIR"
BIN_DIR="$PROJECT_ROOT/bin"

# 创建输出目录
mkdir -p "$BIN_DIR"

echo "🔨 Building S Language LSP Server..."
echo "Project root: $PROJECT_ROOT"
echo "LSP source: $LSP_DIR"
echo "Output: $BIN_DIR"

# 检查 S 编译器
if ! command -v s_c &> /dev/null; then
    if ! command -v s &> /dev/null; then
        echo "❌ Error: S compiler not found!"
        echo "Please ensure S compiler is installed and in PATH"
        exit 1
    fi
    COMPILER="s"
else
    COMPILER="s_c"
fi

echo "Using compiler: $COMPILER"

# 编译 LSP 模块
echo "📦 Compiling LSP modules..."

# 编译顺序：
# 1. lsp_protocol.s - 数据结构
# 2. document_manager.s - 文档管理
# 3. lsp_handler.s - LSP 处理逻辑
# 4. jsonrpc.s - JSON-RPC 通信
# 5. server.s - 主程序

echo "  • Compiling protocol definitions..."
"$COMPILER" -c "$LSP_DIR/lsp_protocol.s" -o "$LSP_DIR/lsp_protocol.o" 2>&1 || {
    echo "❌ Failed to compile lsp_protocol.s"
    exit 1
}

echo "  • Compiling document manager..."
"$COMPILER" -c "$LSP_DIR/document_manager.s" -o "$LSP_DIR/document_manager.o" 2>&1 || {
    echo "❌ Failed to compile document_manager.s"
    exit 1
}

echo "  • Compiling LSP handler..."
"$COMPILER" -c "$LSP_DIR/lsp_handler.s" -o "$LSP_DIR/lsp_handler.o" 2>&1 || {
    echo "❌ Failed to compile lsp_handler.s"
    exit 1
}

echo "  • Compiling JSON-RPC communication..."
"$COMPILER" -c "$LSP_DIR/jsonrpc.s" -o "$LSP_DIR/jsonrpc.o" 2>&1 || {
    echo "❌ Failed to compile jsonrpc.s"
    exit 1
}

echo "  • Compiling server..."
"$COMPILER" -c "$LSP_DIR/server.s" -o "$LSP_DIR/server.o" 2>&1 || {
    echo "❌ Failed to compile server.s"
    exit 1
}

# 链接
echo "🔗 Linking..."
"$COMPILER" -o "$BIN_DIR/s_lsp" \
    "$LSP_DIR/lsp_protocol.o" \
    "$LSP_DIR/document_manager.o" \
    "$LSP_DIR/lsp_handler.o" \
    "$LSP_DIR/jsonrpc.o" \
    "$LSP_DIR/server.o" 2>&1 || {
    echo "❌ Failed to link"
    exit 1
}

# 清理对象文件
echo "🧹 Cleaning up..."
rm -f "$LSP_DIR"/*.o

# 验证输出
if [ -f "$BIN_DIR/s_lsp" ]; then
    chmod +x "$BIN_DIR/s_lsp"
    echo "✅ Build successful!"
    echo "📍 LSP server: $BIN_DIR/s_lsp"
    "$BIN_DIR/s_lsp" --version 2>/dev/null || true
else
    echo "❌ Build failed: Output file not created"
    exit 1
fi

echo ""
echo "📚 Next steps:"
echo "  1. Install VS Code extension:"
echo "     - Copy S Language Support to VS Code extensions:"
echo "       cp -r $PROJECT_ROOT/misc/editor/vscode ~/.vscode/extensions/s-language-support"
echo "  2. Configure extension (optional):"
echo "     - Open VS Code settings"
echo "     - Search for 's.lsp.serverPath'"
echo "     - Set to: $BIN_DIR/s_lsp"
echo "  3. Reload VS Code window (Ctrl+R or Cmd+R)"
