#!/usr/bin/env python3
"""Parse the real frontend without retaining consumed ASTs in the token cursor."""
import os
from pathlib import Path
import resource
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[2]
MEMORY = 512 * 1024 * 1024


def run_bounded(command, work, *, address_space=MEMORY, expected=0):
    def limits():
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
        resource.setrlimit(resource.RLIMIT_CPU, (60, 60))
        resource.setrlimit(resource.RLIMIT_AS, (address_space, address_space))

    log_path = work / "command.log"
    with log_path.open("w+") as log:
        process = subprocess.Popen(
            command, cwd=ROOT, stdout=log, stderr=log, preexec_fn=limits,
            env=dict(os.environ, S_SOURCE_ROOT=str(ROOT)),
        )
        deadline = time.monotonic() + 65
        exceeded = ""
        while process.poll() is None:
            try:
                status = Path(f"/proc/{process.pid}/status").read_text()
                rss = next(int(line.split()[1]) * 1024 for line in status.splitlines()
                           if line.startswith("VmRSS:"))
                if rss > MEMORY:
                    exceeded = "512 MiB resident memory limit exceeded"
            except (FileNotFoundError, StopIteration):
                pass
            if time.monotonic() > deadline:
                exceeded = "65 second wall time limit exceeded"
            if exceeded:
                process.kill()
                break
            time.sleep(0.05)
        process.wait()
        log.seek(0)
        output = log.read()
    if exceeded or process.returncode != expected:
        raise AssertionError(f"{command[0]} exited {process.returncode}: {exceeded}\n{output}")


with tempfile.TemporaryDirectory(prefix="s-canonical-parser-memory-") as directory:
    work = Path(directory)
    main = work / "main.s"
    main.write_text('''package main
import ("compile.internal.syntax"; "compile.internal.ast")
extern "intrinsic" func __host_read_to_string(string path) string
func main() int {
    args := host_args()
    source := __host_read_to_string(args[1])
    parsed, error := compile.internal.syntax.parse_source(source)
    if error.message != "" { panic(error.message) }
    if parsed.pkg != "compile.internal" || len(parsed.items) < 100 { panic("frontend declarations lost") }
    first := false
    last := false
    i := 0
    for i < len(parsed.items) {
        switch parsed.items[i] {
            item.function(declaration): {
                if declaration.sig.name == "compiler_number" {
                    first = declaration.body.is_some() && len(declaration.body.unwrap().statements) > 0
                }
                if declaration.sig.name == "compiler_compile" {
                    last = declaration.body.is_some() && len(declaration.body.unwrap().statements) > 0
                }
            }
            _: (),
        }
        i = i + 1
    }
    if !first || !last { panic("frontend function bodies lost") }
    return 42
}
''')
    sources = [
        "src/option/option.s", "src/result/result.s", "src/prelude/prelude.s",
        "src/fs/fs.s", "src/cmd/compile/internal/ast/ast.s",
        "src/cmd/compile/internal/parser/syntax/syntax.s",
        "src/cmd/compile/internal/parser/syntax/canonical_parser.s",
    ]
    ir = work / "parser.ir"
    binary = work / "parser"
    run_bounded([str(ROOT / "bin/s_seed"), "--compile-native-unit", str(ir),
                 *[str(ROOT / source) for source in sources], str(main)], work)
    # The seed emitter reserves a fixed sparse module of about 9.6 GiB.
    # Bound its actual resident memory separately from that virtual reservation.
    run_bounded([str(ROOT / "bin/s_seed"), "--emit-standalone-amd64", str(ir), str(binary)],
                work, address_space=16 * 1024**3)
    run_bounded([str(ROOT / "misc/scripts/verify_true_selfhost.sh"), str(binary)], work)
    run_bounded([str(binary), str(ROOT / "src/cmd/compile/internal/compiler/frontend.s")],
                work, expected=42)

print("canonical parser retains the real frontend AST under 512 MiB: PASS")
