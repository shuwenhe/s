# Native Redis implementation plan

Goal: native S RESP2 client tested against isolated local Redis.
Architecture and constraints: see design.md. Preserve pre-existing work.
Use executing-plans inline and test-driven-development.

- [x] Protocol: first write S assertions and Python dual-compiler runner; record
  RED; implement bounded incremental flat decoder and RESP array encoder; GREEN.
- [x] Connection and commands: real Redis harness with temporary config, no
  persistence, random loopback port, password/ACL; write S acceptance first;
  implement deadline-aware TCP/TLS, typed wrappers, transactions and pipeline.
- [x] Faults: scripted TCP peers for fragmented, malformed, oversized, truncated,
  disconnected and stalled responses; prove connection invalidation and cleanup.
- [x] Documentation/evidence: runnable local entry point under test/redis,
  Make targets and CI, baseline/rechecks, exact limitations and commands.

Review focus: integer overflow; allocation bounds; partial replies and deadlines;
transaction state after errors; NULL/empty and binary data; no secrets in logs.

## Execution decisions

- User requested direct execution in /home/shuwen/shuwen/s/test/redis: worked in
  the specified checkout and placed every runnable sample under test/redis.
- Existing dirty changes were retained. Their later commit state changed outside
  this task; no unrelated diff was staged, reverted or committed here.
- Full Seed integration stays explicitly blocked; fixing compiler proof rules is
  outside this client change. Protocol is tested with both compilers.
- All client builds use the existing OpenSSL bridge, including TCP-only tests,
  because the client can select TLS at runtime and references its verified API.
- Prefix private helpers with _redis_ to avoid collisions with existing packages.
- Evaluate arrays/options before borrowing; snapshot timeout fields before
  borrowing nested socket/session fields. Do not weaken ownership validation.
- Independent review completed without critical/important findings. Final
  verification must be rerun after source changes; reviewer test overlap was not
  counted as a pass.

Final verification: make redis-check exited 0; both protocol ABIs, real TCP/TLS
Redis, adverse peers and standalone S smoke passed. All 24 existing grouped
regression cases passed. git diff --check passed; compiler/runtime diff is empty.

## S-only test migration

- [x] Replace Redis Python helpers with formatted S entry points: run.s,
  protocol.s, integration.s, tls.s, faults.s, peer/main.s and basic/main.s.
- [x] Read port/TLS settings in S rather than replacing source placeholders.
- [x] Keep lifecycle/build tooling outside test/redis, using shell plus the
  existing OpenSSL bridge; do not add process/runtime functionality for tests.
- [x] Remove Redis Python discovery wrappers and update Make/CI/documentation.
- [x] Run both protocol ABIs and complete TCP/fault/TLS acceptance with Python
  blocked. make redis-check exited 0; independent full rerun also exited 0.
