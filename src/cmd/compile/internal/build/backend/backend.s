package compile.internal.build.backend

use compile.internal.backend_elf64.Build as BuildBinary
use std.fs.MakeTempDir
use std.io.eprintln
use std.process.RunProcess
use std.vec.Vec

func Build(string path, string output) int32 {
    BuildBinary(path, output)
}

func Run(string path) int32 {
    var tempDirResult = MakeTempDir("s-build-")
    if tempDirResult.is_err() {
        eprintln("run failed: could not create temporary output directory");
        return 1
    }

    var outputPath = tempDirResult.unwrap() + "/a.out"
    if Build(path, outputPath) != 0 {
        eprintln("run failed: build step failed");
        return 1
    }

    var runArgv = Vec[string]()
    runArgv.push(outputPath);
    var runResult = RunProcess(runArgv)
    if runResult.is_err() {
        eprintln("run failed: process execution failed");
        return 1
    }
    return 0
}
