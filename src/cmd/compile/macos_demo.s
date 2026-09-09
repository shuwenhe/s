package main

// S编译器macOS演示程序
// 编译并运行: make demo-macos

import "macos_driver"

func main() int {
    println("S编译器macOS平台支持演示")
    println("===============================")
    
    // 检测当前架构
    compiler := macos_driver.macos_compiler_new("hello.s", "hello")
    arch := compiler.detect_architecture()
    println("当前架构: " + arch)
    
    // 检测SDK路径
    sdk := compiler.detect_sdk_path()
    println("SDK路径: " + sdk)
    
    // 创建测试程序
    create_test_program()
    
    // 编译ARM64
    println("\n1. 编译ARM64版本...")
    ret_arm64 := macos_driver.macos_compile_with_arch(
        "demo_hello.s",
        "demo_hello_arm64",
        "arm64"
    )
    if ret_arm64 == 0 {
        println("✓ ARM64编译成功")
    } else {
        println("✗ ARM64编译失败")
    }
    
    // 编译x86_64
    println("\n2. 编译x86_64版本...")
    ret_x86 := macos_driver.macos_compile_with_arch(
        "demo_hello.s",
        "demo_hello_x86",
        "x86_64"
    )
    if ret_x86 == 0 {
        println("✓ x86_64编译成功")
    } else {
        println("✗ x86_64编译失败")
    }
    
    // 创建Universal Binary
    println("\n3. 创建Universal Binary...")
    ret_universal := create_universal_binary()
    if ret_universal == 0 {
        println("✓ Universal Binary创建成功")
    } else {
        println("✗ Universal Binary创建失败")
    }
    
    println("\n演示完成！")
    println("生成的文件:")
    println("  - demo_hello_arm64: ARM64可执行文件")
    println("  - demo_hello_x86: x86_64可执行文件")
    println("  - demo_hello_universal: Universal Binary")
    
    return 0
}

func create_test_program() {
    // 创建一个简单的S程序用于演示
    program := "package main\n\nfunc main() int {\n    println(\"Hello from S on macOS!\")\n    return 0\n}\n"
    
    // 写入测试文件
    result := __host_write_text_file("demo_hello.s", program)
    if result != 0 {
        println("警告: 无法创建测试文件")
    }
}

func create_universal_binary() int {
    // 尝试创建Universal Binary
    // 注意: 这需要两个架构的目标文件都已生成
    
    cmd := "lipo -create demo_hello_arm64 demo_hello_x86 -output demo_hello_universal 2>/dev/null"
    ret := system(cmd)
    return ret
}

// 外部函数
extern "intrinsic" func __host_write_text_file(string path, string contents) int;
extern "intrinsic" func system(string cmd) int;

func println(string s) {
    // 简单的打印函数
    // 实际使用外部函数
}
