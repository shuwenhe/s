# S distribution bootstrap tools

This directory contains the staged native bootstrap driver and its audit
helpers. `native-bootstrap.sh` uses the trusted C seed only for stage 1, then
requires the S compiler to produce stages 2 and 3 and verifies both IR and
binary convergence.

Run the supported entrypoints through the repository makefile:

```sh
make native-bootstrap
make true-selfhost-check
make bootstrap-audit
```
