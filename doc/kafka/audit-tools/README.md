# Reproducible audit diagnostics

These are **audit-only** programs, not new client functionality. They preserve the
exact diagnostic inputs used on 2026-11-15. Native library/compiler/runtime sources
are not changed. Raw artifacts and exact successful commands are retained under
`.bootstrap/kafka-audit/audit-20261115/` in the audited workspace.

To reproduce the Consumer size sweep plus 30-minute canonical replay in a **new**
repository-local output directory, from `/root/shuwen/s`:

```sh
python3 doc/kafka/audit-tools/reproduce-memory.py .bootstrap/kafka-audit/MY_FRESH_MEMORY_RUN
```

Requirements: existing `bin/s_seed`, `bin/s_compiler`, existing repository Java
runtime at `.bootstrap/kafka-broker/java`, existing checksum-verified Kafka cache,
`javac`, Python, native build tools, permission to create loopback sockets and read
child `/proc` status/smaps. This audit used the preexisting runtime/cache and did
not install anything. The existing broker helper can download a missing Kafka
archive; provision/verify the repository-local cache before running if downloads
are unwanted. Do not share ports 39092/39093/39094 with another test. Output must
not exist. The wrapper copies the harness into the requested directory and fixes
its run path. It starts/stops only owned fixtures using the repository helper.

The sweep uses a separate official Java Producer as test input, measures only the
native Consumer PID, replays one record with seek/ACK/commit, and intentionally
loses its session once. A 1 MiB payload is deliberately rejected by the current
Consumer cap; recorded child exit 4 is not successful consumption. Each supported
size has 16 deliveries. The 30-minute canonical case uses 1 KiB input. It is a
replay/lifecycle experiment, not sustained newly produced traffic or certification
of all sizes/compiler paths. See KAFKA_MEMORY_AUDIT.md for interpretation.

`probe.s` and `header-probe.s` reproduce local ACK/cleanup/decoder-cap and malformed
header-name behavior. Their run scripts preserve the original audit output paths;
copy/adapt those paths before rerunning so historical artifacts are retained.
`summarize.py` preserves the original evidence-summary procedure and expects the
original full acceptance/edge/commit evidence layout; it is not a general test tool.
The separate stock full acceptance runner currently has the duplicate-main issue
T-01. The successful copied builder/acceptance scripts are retained in the original
evidence directory and documented in the capability matrix.

The remote-idle close reproduction is retained as `idle-close.s`,
`idle-close-run.sh` and `idle-broker-helper.sh`. The copied helper changes only
owned test-cluster idle timeout to 5000ms. Like other original run scripts it
uses original audit output paths; adapt fresh paths before rerunning. Its
expected observed failure is client exit 8, close code 4/native 104.
