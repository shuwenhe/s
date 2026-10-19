# S distribution bootstrap tools

This directory contains the staged native bootstrap driver and its audit
helpers. `native-bootstrap.sh` uses the trusted C seed only for stage 1, then
requires the S compiler to produce stages 2 and 3 and verifies both IR and
binary convergence.

The S-written controller in `bootstrap.s` uses the production import closure
from `source_closure.sh` and invokes the previous stage for both compilation
and emission. Run from the repository root, with absolute paths and a new
output directory whose parent already exists:

```sh
make s-dist-bootstrap-bin
.bootstrap/s-dist/s-dist-bootstrap "$PWD" "$PWD/.bootstrap/s-dist/run-001" "$PWD/bin/s_seed"
```

The controller retains failed artifacts, reports the failing stage and child
exit status, checks nonempty IR and executable ELF, prints producer/artifact
SHA-256 values, and compares raw stage2/stage3 IR and binaries. Its executable
currently uses the Seed host runtime for process and file services. Building
the controller does not establish compiler self-hosting. Byte equality alone
does not establish IR-to-Native authority; that remains a separate gate.

Run the supported entrypoints through the repository makefile:

```sh
make native-bootstrap
make true-selfhost-check
make bootstrap-audit
```
