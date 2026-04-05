# slate

Minimal Slate compiler prototype.

Current MVP scope:

- reads `hello.s`
- lexes / parses / semantically checks a minimal subset
- emits a native `x86_64 Linux` binary without going through C

Self-hosting status:

- Python bootstrap compiler lives in `/app/slate/slatec`
- S-language compiler source now starts in `/app/slate/slatec_s`
- bootstrap notes live in `/app/slate/docs/self_hosting.md`

Example:

```bash
cd /app/slate
python3 -m slatec build /tmp/hello.s -o /tmp/hello
/tmp/hello
```

Minimal supported source shape:

```s
package main

func main() {
    println("hello, world")
}
```
