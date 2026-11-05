# Native S Snake

From the repository root:

```
./bin/s build examples/snake/main.s -o /tmp/snake
/tmp/snake
/tmp/snake --self-test
```

Linux/amd64, ANSI terminal at least 38 columns by 16 rows. Arrows or WASD steer; reverse turns are ignored, and only one direction change is applied per simulation tick. Q, Escape, Ctrl-C or EOF exits. Food uses a reproducible non-cryptographic generator, with linear probing to choose an empty cell. Wall/body collision or filling the board ends the game.

All application logic is S. A bounded board uses an S `int[]` body with ordinary value semantics; every tick constructs the next body. `std.time` supplies monotonic frame timing and kernel sleeping, `std.input` supplies raw nonblocking keyboard parsing, and `std.terminal` supplies buffered dirty-cell rendering. Initialization clears once; subsequent frames update only the old tail, old/new head, changed food and score. There is no C++/ncurses application dependency.

Explicit cleanup attempts both input and output restoration and propagates failures. Runtime cleanup retries active sessions on normal return. Fatal signals and forced termination retain the limitations documented in the module references.

`python3 test/stdlib-native/test_snake.py -v` builds through the public import resolver, executes deterministic rules and a real PTY game session, and checks exact restoration, frame output and CPU use. `--self-test` needs no terminal.
