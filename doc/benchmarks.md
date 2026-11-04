# Native performance measurements

Run from the repository root after building the compiler:

```sh
python3 misc/scripts/benchmark-native.py /tmp/s-native-benchmark-new
```

The output directory must not exist. It retains generated S and C sources,
assembly, executables, compiler hash, source revision and working-tree diff,
tool versions, per-command logs, wall time and peak RSS. The harness copies
itself into the evidence directory. `--compiler` selects a preserved compiler;
`--cc` selects the C compiler. `--runs` defaults to five and requires at least
three measured executions after a warmup.

The sum workload takes its iteration count at runtime, checking the arithmetic
sum of twenty million integers. Recursive Fibonacci checks fib(32). Every
execution must return 42; the harness fails on other statuses. C uses `-O2`.
Optimizers can transform the workloads differently; no volatile constraints
force identical machine instructions. These scalar workloads do not measure
allocation, GC, I/O, concurrency or large-project compilation.

GNU time measures peak RSS, and Python measures elapsed wall time around each
process. Short executions include process startup and measurement overhead;
timer resolution limits interpretation. Run on an otherwise idle machine for
performance comparisons. Record CPU frequency policy, system load and repeated
samples before attributing a change to an optimization.

An initial development run during the production audit completed both workloads
with five successful executions per language. Evidence is retained at
`/app/shuwen/production-mission-20261104/benchmarks-signed-v3/`. It ran concurrently
with compiler checks and a bootstrap, so it establishes harness operation and
correct results rather than a release performance baseline. Final measurements
at the accepted compiler revision remain required.

`test/benchmarks/run.sh` is a historical, separate benchmark. Its no-GC wording
and legacy assumptions do not describe the canonical collector-backed native
path. Do not combine its results with this harness or infer a no-GC guarantee.
