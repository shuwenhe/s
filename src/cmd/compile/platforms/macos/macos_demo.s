package main

import "macos_driver"

func main() int {
    println("S编译器macOS平台支持演示")
    println("===============================")

    compiler := macos_driver.macos_compiler_new("hello.s", "hello")
    arch := compiler.detect_architecture()
    println("当前架构: " + arch)

    sdk := compiler.detect_sdk_path()
    println("SDK路径: " + sdk)

    create_test_program()

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

    program := "package main\n\nfunc main() int {\n    println(\"Hello from S on macOS!\")\n    return 0\n}\n"

    result := __host_write_text_file("demo_hello.s", program)
    if result != 0 {
        println("警告: 无法创建测试文件")
    }
}

func create_universal_binary() int {

    cmd := "lipo -create demo_hello_arm64 demo_hello_x86 -output demo_hello_universal 2>/dev/null"
    ret := system(cmd)
    return ret
}

extern "intrinsic" func __host_write_text_file(string path, string contents) int;
extern "intrinsic" func system(string cmd) int;

func println(string s) {

}