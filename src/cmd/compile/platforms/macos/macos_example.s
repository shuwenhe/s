package macos_example

import "macos_driver"

// S编译器macOS平台使用示例

// 示例1：编译为ARM64 (Apple Silicon)
func compile_for_apple_silicon(string source_file, string output_file) int {
    return macos_driver.macos_compile_with_arch(source_file, output_file, "arm64")
}

// 示例2：编译为x86_64 (Intel)
func compile_for_intel_mac(string source_file, string output_file) int {
    return macos_driver.macos_compile_with_arch(source_file, output_file, "x86_64")
}

// 示例3：通用二进制（Universal Binary）
func compile_universal_binary(string source_file, string output_file) int {
    // 编译两个架构的版本
    ret_arm64 := macos_driver.macos_compile_with_arch(source_file, output_file + ".arm64", "arm64")
    ret_x86_64 := macos_driver.macos_compile_with_arch(source_file, output_file + ".x86_64", "x86_64")
    
    if ret_arm64 != 0 || ret_x86_64 != 0 {
        return -1
    }
    
    // 使用lipo命令创建Universal Binary
    ret := system("lipo -create " + output_file + ".arm64 " + output_file + ".x86_64 -output " + output_file)
    return ret
}

// 示例4：带完整配置的编译
func compile_with_config(string source_file, string output_file) int {
    compiler := macos_driver.macos_compiler_new(source_file, output_file)
    
    // 自定义配置
    compiler.config.arch = "arm64"
    compiler.config.deployment_target = "12.0.0"
    compiler.config.use_clang = true
    
    // 执行编译
    return compiler.compile()
}

func system(string cmd) int {
    // 占位符 - 实际由外部提供
    return 0
}
