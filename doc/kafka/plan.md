# Native Kafka implementation plan

Implement in S, with formatted code and shell-only external lifecycle tooling.
Work in the specified checkout; preserve existing Redis/MySQL/compiler sources.
Baseline revision: f5bfe2153743c23d6dc721c9ef17d317b9bb8f8b.

## Audit and design

TCP supplies IPv4 literal dial, partial read/write, EOF and idempotent close. TLS
supplies mandatory CA/hostname verification with the existing system OpenSSL
bridge. Database wire provides bounded binary cursor patterns; Redis provides
single-owner synchronous transport/deadline/error patterns and S peers. Integers
are signed 64-bit; strings hold arbitrary bytes; arrays are dynamic but bounded.
Bind expressions before borrowed arguments and copy timeout fields before
borrowing nested handles. Do not copy live connection owners. Package-private
helpers use a Kafka-specific prefix. No compiler/runtime changes planned.

Select Kafka3.9.1 / Java21, legacy non-flexible API versions verified against
ApiVersions on every broker connection: ApiVersions0, Metadata1, Produce3,
Fetch4, ListOffsets1. Implement compact/varint/tagged primitives in isolation but
do not claim negotiated flexible APIs until used and validated. Uncompressed
magic2 record batches carry CRC32C, null values and headers. Use synchronous
non-idempotent acknowledged sends with no automatic retry. Manual consumers own
one assigned partition and advance only after a complete validated delivery.

Modules: config/error/protocol/record/transport/client/metadata/producer/consumer/
offset in src/std/kafka. All assertions/peers/examples in test/kafka (no examples
folder, Python, alternate-language Kafka client). Shell build/check/broker tools
in misc/scripts. Public error categories follow std.redis/std.database conventions.

## Gates

- [ ] Baseline: make redis-check, make mysql-unit-check, make compiler; record
  compiler stage availability and hashes. Verify clean starting worktree.
- [ ] Phase1 RED: S binary/record/framing assertions fail before implementation.
  GREEN: bounded big-endian/nullable/compact/varint/tag codecs, CRC32C, recordbatch2
  parsing and negotiation/metadata parsing tested on Seed/native where supported.
- [ ] Phase2: real isolated KRaft metadata and version negotiation; follow returned
  broker IDs/leader endpoints rather than assume bootstrap is leader.
- [ ] Phase3: synchronous producer acknowledges 100 real records; validate returned
  offsets, binary/null/empty/headers and explicit/default partition selection.
- [ ] Phase4: Fetch/ListOffsets, assignment/seek/earliest/latest; verify all payloads,
  headers/offsets/order, multiple partitions, invalid inputs, restarts and cleanup.
- [ ] Phase5: S fault peers and verified TLS to real broker when prerequisites pass;
  no unknown-state reuse or automatic retries. Document later groups/advanced
  delivery features individually, without unsupported claims.
- [ ] Make/CI, runnable S examples, benchmark actual sizes/counts/time/memory,
  independent review and final regressions. make kafka-check must return zero only
  after required unit, real-broker and fault checks all pass; missing tools fail.

Review focus: frame/cursor overflow; CRC coverage/record truncation; nullable versus
empty; ApiVersions compatibility; correlation IDs; broker routing; consumer
seek into a record batch; offsets never advance on decode failure; total deadlines;
cleanup and non-idempotent ambiguous delivery outcomes.
