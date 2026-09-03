# S AOT compilation

The AOT backend lowers S seed IR to target assembly, assembles it to an object,
and links it with the freestanding S runtime. The resulting executable does not
contain the IR interpreter or an embedded copy of the input IR.

```sh
./bin/s_seed program.s program.ir
S_SOURCE_ROOT="$PWD" ./bin/s_seed --emit-aot program.ir program
./program
```

Intermediate outputs are available for toolchain integration:

```sh
./bin/s_seed --emit-aot-asm program.ir program.S
./bin/s_seed --emit-aot-obj program.ir program.o
```

`S_TARGET_OS` and `S_TARGET_ARCH` select the target. The currently implemented
AOT target is `linux/amd64`, which emits a static ELF executable through `as`
and `ld`. Unsupported targets and unsupported IR opcodes are hard errors; the
compiler never silently falls back to interpretation.

`--emit-bin` remains available for compatibility. It embeds IR in the portable
runtime and is not AOT compilation.
