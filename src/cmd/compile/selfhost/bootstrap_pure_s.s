package main
import (
    "std.fs"
    "std.io"
    "std.io_syscall"
    "std.process"
)
extern "intrinsic" func host_args() string[];
func main() {
    args := host_args()
    compiler_src := "./src/cmd/compile/selfhost/compiler.s"
    output_dir := "./.bootstrap/selfhost"
    if len(args) == 2 {
        output_dir = args[1]
    } else if len(args) != 1 {
        std.io.eprintln("usage: s_bootstrap_pure_s [output-dir]")
        return 2
    }
    seed_compiler := "./bin/s_seed"
    ir_codegen_bin := "./src/cmd/compile/selfhost/ir_to_binary"
    std.io.eprintln("")
    std.io.eprintln("=== S Compiler Pure S Bootstrap ===")
    std.io.eprintln("")
    std.io.eprintln("source: " + compiler_src)
    std.io.eprintln("workdir: " + output_dir)
    std.io.eprintln("seed: " + seed_compiler)
    std.io.eprintln("ir-codegen: " + ir_codegen_bin)
    if !ensure_dir(output_dir) {
        return 1
    }
    return bootstrap_three_stage(compiler_src, output_dir, seed_compiler, ir_codegen_bin)
}

func ensure_dir(string path) bool {
    if std.io_syscall.mkdir(path) != 0 {
        return false
    }
    true
}

func bootstrap_three_stage(
    string compiler_src,
    string output_dir,
    string seed_compiler,
    string ir_codegen_bin
) int {
    stage1_ir := output_dir + "/stage1.ir"
    stage1_bin := output_dir + "/stage1"
    stage2_ir := output_dir + "/stage2.ir"
    stage2_bin := output_dir + "/stage2"
    stage3_ir := output_dir + "/stage3.ir"
    stage3_bin := output_dir + "/stage3"
    std.io.eprintln("[1/5] building stage1 IR with the trusted seed")
    if std.process.run_process([seed_compiler, compiler_src, stage1_ir]) != 0 {
        std.io.eprintln("bootstrap command failed")
        return 1
    }
    std.io.eprintln("[2/5] lowering stage1 IR to a runnable compiler")
    if std.process.run_process([seed_compiler, "--emit-standalone-amd64", stage1_ir, stage1_bin]) != 0 {
        std.io.eprintln("bootstrap command failed")
        return 1
    }
    std.io.eprintln("[3/5] recompiling compiler.s with stage1")
    if std.process.run_process([stage1_bin, compiler_src, stage2_ir]) != 0 {
        std.io.eprintln("bootstrap command failed")
        return 1
    }
    if std.process.run_process([stage1_bin, "--emit-bin", stage2_ir, stage2_bin]) != 0 {
        std.io.eprintln("bootstrap command failed")
        return 1
    }
    std.io.eprintln("[4/5] recompiling compiler.s with stage2")
    if std.process.run_process([stage2_bin, compiler_src, stage3_ir]) != 0 {
        std.io.eprintln("bootstrap command failed")
        return 1
    }
    if std.process.run_process([stage2_bin, "--emit-bin", stage3_ir, stage3_bin]) != 0 {
        std.io.eprintln("bootstrap command failed")
        return 1
    }
    std.io.eprintln("[5/5] verifying convergence")
    if std.process.run_process(["cmp", stage2_ir, stage3_ir]) != 0 {
        std.io.eprintln("bootstrap failed: stage2.ir and stage3.ir differ")
        return 1
    }
    if std.process.run_process(["cmp", stage2_bin, stage3_bin]) != 0 {
        std.io.eprintln("bootstrap failed: stage2 and stage3 binaries differ")
        return 1
    }
    manifest := make_manifest(stage1_ir, stage1_bin, stage2_ir, stage2_bin, stage3_ir, stage3_bin)
    if std.fs.write_text_file(output_dir + "/manifest.txt", manifest) != 0 {
        std.io.eprintln("bootstrap failed: unable to write manifest")
        return 1
    }
    std.io.eprintln("bootstrap complete: stage2 and stage3 converge")
    std.io.eprintln("installed candidate: " + stage2_bin)
    0
}

func make_manifest(
    string stage1_ir,
    string stage1_bin,
    string stage2_ir,
    string stage2_bin,
    string stage3_ir,
    string stage3_bin
) string {
    out := "s-bootstrap-manifest-v1\n"
    out = out + "stage1.ir=" + stage1_ir + "\n"
    out = out + "stage1=" + stage1_bin + "\n"
    out = out + "stage2.ir=" + stage2_ir + "\n"
    out = out + "stage2=" + stage2_bin + "\n"
    out = out + "stage3.ir=" + stage3_ir + "\n"
    out = out + "stage3=" + stage3_bin + "\n"
