package main

use fmt
use compile.internal.codegen

func main() {
    // 运行完整的演示报告
    report := generate_complete_demo_report()
    fmt.println(report)
    
    // 可选：输出到文件
    // write_report_to_file(report)
}

// 演示如何使用编译器
func demonstrate_compiler_usage() string {
    result := "\n=== 编译器使用示例 ===\n\n"
    
    // 创建编译器实例
    result = result + "1. 创建编译器:\n"
    result = result + "   compiler := make_s_compiler_full()\n\n"
    
    // 编译
    result = result + "2. 编译源代码:\n"
    result = result + "   obj_data := compiler.compile_and_generate_object()\n\n"
    
    // 获取信息
    result = result + "3. 获取编译信息:\n"
    result = result + "   info := compiler.dump_compilation_info()\n\n"
    
    result = result + "4. 生成的对象文件格式:\n"
    result = result + "   - ELF 64-bit，x86-64 架构\n"
    result = result + "   - 包含 .text 节 (机器码)\n"
    result = result + "   - 包含 .symtab 节 (符号表)\n"
    result = result + "   - 包含 .rel.text 节 (重定位信息)\n"
    result = result + "   - 包含 .shstrtab 节 (节名字符串表)\n\n"
    
    result
}

// 演示直接机器码生成
func demonstrate_machine_code_generation() string {
    result := "\n=== 直接机器码生成过程 ===\n\n"
    
    result = result + "高级语言代码:\n"
    result = result + "  main() {\n"
    result = result + "    exit(42)\n"
    result = result + "  }\n\n"
    
    result = result + "翻译为汇编:\n"
    result = result + "  main:\n"
    result = result + "      push rbp\n"
    result = result + "      mov rbp, rsp\n"
    result = result + "      mov rax, 60        // sys_exit\n"
    result = result + "      mov rdi, 42        // exit code\n"
    result = result + "      syscall\n"
    result = result + "      pop rbp\n"
    result = result + "      ret\n\n"
    
    result = result + "直接生成机器码 (无 IR):\n"
    result = result + "  55                    // push rbp\n"
    result = result + "  48 89 e5              // mov rbp, rsp\n"
    result = result + "  b8 3c 00 00 00        // mov rax, 60\n"
    result = result + "  bf 2a 00 00 00        // mov rdi, 42\n"
    result = result + "  0f 05                 // syscall\n"
    result = result + "  5d                    // pop rbp\n"
    result = result + "  c3                    // ret\n\n"
    
    result
}

// 展示与 Go 编译器的相似之处
func show_go_similarities() string {
    result := "\n=== 与 Go 编译器的相似设计 ===\n\n"
    
    result = result + "1. 直接机器码生成\n"
    result = result + "   Go: cmd/compile/internal/ssagen\n"
    result = result + "   S:  compile.internal.codegen\n\n"
    
    result = result + "2. AMD64 代码生成\n"
    result = result + "   Go: cmd/compile/internal/amd64\n"
    result = result + "   S:  compile.internal.codegen.encoding\n\n"
    
    result = result + "3. 对象文件生成\n"
    result = result + "   Go: cmd/link/internal/ld\n"
    result = result + "   S:  compile.internal.obj\n\n"
    
    result = result + "4. 符号和重定位\n"
    result = result + "   Go: cmd/compile/internal/ir + objw\n"
    result = result + "   S:  compile.internal.codegen.relocation + symbol\n\n"
    
    result = result + "关键特性:\n"
    result = result + "  ✓ 无中间表示 (IR-free)\n"
    result = result + "  ✓ 直接从 AST 生成机器码\n"
    result = result + "  ✓ 架构特定优化 (x86-64)\n"
    result = result + "  ✓ ELF 格式对象文件\n"
    result = result + "  ✓ System V ABI 遵从\n\n"
    
    result
}

// 编译系统的完整流程图
func show_compilation_pipeline() string {
    result := "\n=== 编译管道 ===\n\n"
    
    result = result + "┌────────────┐\n"
    result = result + "│ 源代码文件 │  input.s\n"
    result = result + "└──────┬─────┘\n"
    result = result + "       │\n"
    result = result + "       ▼\n"
    result = result + "┌──────────────┐\n"
    result = result + "│ Lexer        │  tokenization\n"
    result = result + "└──────┬───────┘\n"
    result = result + "       │\n"
    result = result + "       ▼\n"
    result = result + "┌──────────────┐\n"
    result = result + "│ Parser       │  AST building\n"
    result = result + "└──────┬───────┘\n"
    result = result + "       │\n"
    result = result + "       ▼\n"
    result = result + "┌──────────────────────────────┐\n"
    result = result + "│ Code Generator (Direct)      │  NO INTERMEDIATE REPRESENTATION\n"
    result = result + "│ - Encoding                   │\n"
    result = result + "│ - Machine Code Generation    │\n"
    result = result + "└──────┬───────────────────────┘\n"
    result = result + "       │\n"
    result = result + "       ▼\n"
    result = result + "┌──────────────────┐\n"
    result = result + "│ Symbol Table     │  symbols\n"
    result = result + "│ Relocation Info  │  relocations\n"
    result = result + "└──────┬───────────┘\n"
    result = result + "       │\n"
    result = result + "       ▼\n"
    result = result + "┌──────────────────┐\n"
    result = result + "│ ELF Generator    │  object.o\n"
    result = result + "└──────┬───────────┘\n"
    result = result + "       │\n"
    result = result + "       ▼\n"
    result = result + "┌──────────────────┐\n"
    result = result + "│ Linker           │  executable\n"
    result = result + "└──────────────────┘\n\n"
    
    result
}

// 主要信息总结
func summary() string {
    result := "\n"
    result = result + "════════════════════════════════════════════════════════════════\n"
    result = result + "             S 语言编译器 - 参考 Go 的直接机器码生成\n"
    result = result + "════════════════════════════════════════════════════════════════\n\n"
    
    result = result + "项目目标:\n"
    result = result + "  为 S 语言实现一个高效的、参考 Go 编译器设计的直接机器码生成器\n\n"
    
    result = result + "核心模块:\n"
    result = result + "  1. encoding.s               - AMD64 指令编码\n"
    result = result + "  2. machine.s                - 指令流和机器码构造\n"
    result = result + "  3. codegen.s                - 代码生成上下文\n"
    result = result + "  4. go_style_codegen.s       - 高级代码生成器\n"
    result = result + "  5. elf64.s                  - ELF 数据结构\n"
    result = result + "  6. go_style_elf_generator.s - ELF 文件生成\n"
    result = result + "  7. relocation.s             - 重定位处理\n"
    result = result + "  8. symbol.s                 - 符号表管理\n"
    result = result + "  9. compiler_integration.s   - 系统集成\n\n"
    
    result = result + "技术特点:\n"
    result = result + "  • 直接生成机器码，无中间表示 (IR)\n"
    result = result + "  • 支持 AMD64 (x86-64) 架构\n"
    result = result + "  • 生成 ELF 格式可重定位对象文件\n"
    result = result + "  • 完整的符号表和重定位支持\n"
    result = result + "  • 遵循 System V AMD64 ABI\n"
    result = result + "  • 参考 Go 1.x 编译器的架构\n\n"
    
    result = result + "编译过程:\n"
    result = result + "  源代码 → Lexer → Parser → Direct Code Gen → ELF → 链接器 → 可执行文件\n\n"
    
    result = result + "════════════════════════════════════════════════════════════════\n\n"
    
    result
}
