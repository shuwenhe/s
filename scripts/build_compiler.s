package main

use std.env.get as env_get
use std.env.args as env_args
use std.fs.file_exists
use std.prelude.len
use std.io.println

func main() int {
    let args = env_args()
    
    // Usage: build_compiler.s <arch>
    // Returns path to compiled binary
    
    if args.len() < 2 {
        println("usage: build_compiler.s <arch>")
        return 1
    }
    
    let arch = args[1]
    
    // For now, return the path to bin/s (already compiled and self-hosted)
    let compiler_path = ""
    
    if arch == "x86_64" || arch == "amd64" {
        compiler_path = "./bin/s"
    } else if arch == "arm64" || arch == "aarch64" {
        compiler_path = "./bin/s"
    } else {
        println("unsupported architecture: " + arch)
        return 1
    }
    
    // Verify the compiler exists
    if !file_exists(compiler_path) {
        println("compiler not found: " + compiler_path)
        return 1
    }
    
    // Output the path
    println(compiler_path)
    
    0
}
