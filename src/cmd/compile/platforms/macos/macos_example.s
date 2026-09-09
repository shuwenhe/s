package macos_example

import "macos_driver"

func compile_for_apple_silicon(string source_file, string output_file) int {
    return macos_driver.macos_compile_with_arch(source_file, output_file, "arm64")
}

func compile_for_intel_mac(string source_file, string output_file) int {
    return macos_driver.macos_compile_with_arch(source_file, output_file, "x86_64")
}

func compile_universal_binary(string source_file, string output_file) int {

    ret_arm64 := macos_driver.macos_compile_with_arch(source_file, output_file + ".arm64", "arm64")
    ret_x86_64 := macos_driver.macos_compile_with_arch(source_file, output_file + ".x86_64", "x86_64")

    if ret_arm64 != 0 || ret_x86_64 != 0 {
        return -1
    }

    ret := system("lipo -create " + output_file + ".arm64 " + output_file + ".x86_64 -output " + output_file)
    return ret
}

func compile_with_config(string source_file, string output_file) int {
    compiler := macos_driver.macos_compiler_new(source_file, output_file)

    compiler.config.arch = "arm64"
    compiler.config.deployment_target = "12.0.0"
    compiler.config.use_clang = true

    return compiler.compile()
}

func system(string cmd) int {

    return 0
}