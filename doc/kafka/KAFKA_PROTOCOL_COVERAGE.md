# Kafka protocol coverage audit

Date: 2026-11-15. Scope is a bounded Kafka 3.9.1 client subset. No full Kafka
protocol, modern-broker-version compatibility, or AdminClient claim is made.
Status/severity definitions and evidence root `E` are in the
[capability matrix](KAFKA_CAPABILITY_MATRIX.md). Selected versions are read directly
from request builders and dispatch code, not inferred from data type names.

## APIs

In this table PASS refers to the selected version and bounded implementation.
Each implemented API has bounded encoding, response consumption with `finished`,
and error propagation. All Kafka source names are under `src/std/kafka/`.
Unit means S codec tests; peer means scripted native socket fixtures; real means
an Apache broker, not a protocol peer. Fresh run results are in the capability
matrix's execution ledger.

| API (key), status | Version | Request encoder / response decoder | Error behavior | Unit / peer coverage | Real-broker verification | Missing behavior / severity / action |
| --- | ---: | --- | --- | --- | --- | --- |
| ApiVersions (18), PASS | 0 | `broker.s::broker_build_api_versions_request` / `broker_parse_api_versions_response` | Rejects duplicate keys, invalid ranges, trailing/truncated bodies; signed broker error preserved. | `test/kafka/unit/main.s`, `fault/{client,peer}.s`, Consumer transport fixtures | Fresh Consumer matrix negotiates each role; broker real suite separately. | Fixed version, no flexible response-header handling; P2; qualify other brokers before broadening. |
| Metadata (3), PASS | 4 | `consumer_metadata.s::consumer_build_metadata` / `consumer_parse_metadata` | Topic/partition errors, duplicate/missing identities and cap violations explicit. | `consumer-unit/protocol.s`; `consumer-phase1/main.s` | Fresh multi-topic, partition growth and recovery cases. | No all-topics/null request, topic IDs or epoch-aware redirects; P2; extend only for demonstrated need. |
| Produce (0), PASS | 3 | `produce.s::build_produce_request` / `parse_produce_response` | Explicit ACK modes, topic/partition identity, broker codes and malformed responses. | `producer-unit/main.s`, `producer-fault/{client,peer}.s` | Producer-to-Consumer tests; separate official console-consumer oracle suite. | No idempotence, transactions, compression, routing or retry; P1; roadmap gates apply. |
| Fetch (1), PARTIAL | 4 | `consumer_fetch.s::consumer_build_fetch` / `consumer_parse_fetch`; `consumer_decode.s::consumer_decoder_step` | Identity, frame, CRC, record boundaries, unsupported codec and broker errors explicit. | `consumer-unit/{protocol,decode_cases,transport}.s`; `consumer-fault/{client,peer}.s` | Fresh exact-field phase1, offsets, benchmark and memory size sweep. | One partition/request, read-uncommitted, <=4096 decoded records, 1 MiB full frame; P1/C-03/M-01; bounded-window redesign/qualification. |
| ListOffsets (2), PASS | 1 | `consumer_offset_protocol.s::consumer_build_list_offsets`, `_kc_build_offsets` / `consumer_parse_offsets(api=2)` | Expected partitions, duplicates, omissions, signed status; nonnegative successful initial position. | `consumer-unit/protocol.s`; `consumer-offsets/main.s` | Fresh earliest/latest initialization and offset scenarios. | High-level timestamp search absent although codec accepts timestamps; no leader-epoch fencing; P2; scope docs. |
| FindCoordinator (10), PASS | 1 | `consumer_group_protocol.s::consumer_build_find` / `consumer_parse_find` | Only group coordinator key type; validates successful endpoint and status. | `consumer-unit/group_wire.s` | Fresh group discovery/recovery; edge failover assertions separately. | No transaction coordinator or multi-key lookup; P2; defer transaction APIs. |
| JoinGroup (11), PASS | 2 | `consumer_group_protocol.s::consumer_build_join` / `consumer_parse_join` | Validates range protocol, member IDs and member subscriptions; broker errors returned. | `consumer-unit/{group,group_wire}.s` | Fresh single/pair/empty, lapse and rejoin cases. | Classic only, <=128 members, no static membership; P2; retain explicit classic restriction. |
| SyncGroup (14), PASS | 1 | `consumer_group_protocol.s::consumer_build_sync` / `consumer_parse_sync`; `consumer_assign.s` assignment codecs | Rejects unknown/unsubscribed/duplicate partitions and malformed assignments. | `consumer-unit/{group,group_wire}.s` | Fresh disjoint/complete Range and empty assignments. | No cooperative/sticky or incremental assignment; P2; defer until reliability gate. |
| Heartbeat (12), PASS with service | 1 | `consumer_group_protocol.s::consumer_build_membership(api=12)` / `consumer_parse_membership` | Generation/member included; rebalance/session/coordinator failures drive recovery. | `consumer-unit/liveness.s`, `consumer-group/main.s` | Fresh >session liveness, lapse/max-poll and processing delays. | Caller must service; no background heartbeat; P1 deployment contract. |
| LeaveGroup (13), PARTIAL | 1 | `consumer_group_protocol.s::consumer_build_membership(api=13)` / `consumer_parse_membership` | Close returns failure if reconnect/leave fails; releases sockets regardless. | `consumer-unit/liveness.s`, group reconnect scenario | Fresh reconnectclose; real member departure cases. | Remote-idle group socket fails close without reconnect (R-02/P1); repair bounded remote-EOF recovery. Batched static-member Leave absent. |
| OffsetCommit (8), PASS within scope | 2 | `consumer_offset_protocol.s::consumer_build_offset_commit` / `consumer_parse_offsets(api=8)`; `consumer_ack.s::consumer_apply_commit` | Per-partition response confirmation, generation/epoch fencing, error priority, terminal authorization. | `consumer-unit/offsets.s`, `consumer-commit-fault/{client,peer}.s` | Fresh manual/auto/restoration; edge raw stale-generation commit. | Ambiguous lost response, no transactional offset commits; P1; maintain ACK/commit separation. |
| OffsetFetch (9), PASS | 2 | `consumer_offset_protocol.s::consumer_build_offset_fetch` / `consumer_parse_offsets(api=9)` | Partition and global errors, missing offset=-1, identities and cap checks. | `consumer-unit/protocol.s`, offsets tests | Fresh restart/replay and restoration. | No require-stable read or multi-group fetch; P2; document scope. |
| DescribeGroups (15), PASS within diagnostic scope | 1 | `consumer_describe.s::consumer_build_describe` / `consumer_parse_describe` | Exactly requested group, bounded members, duplicate/null fields and group status. | `consumer-unit/describe.s`; diagnostic helper in scenarios | `consumer-scenarios/main.s` invokes broker diagnostic during processing/recovery. | No high-level administration object or full member payload decoding; P3; keep diagnostic scope. |
| ListGroups (16), NOT IMPLEMENTED | — | No Kafka builder/parser/dispatcher found | No client handling | None | None | Group enumeration unavailable; P3; defer. |

`consumer_supports` verifies the selected API version in role-local ApiVersions
advertisements. Codecs being callable directly do not automatically negotiate.
LeaveGroup close uses its membership builder without a separate LeaveGroup
advertisement check; successful tests establish v1 compatibility with 3.9.1, not
uniform checking of every low-level helper.

## Framing and record scope

- Requests use non-flexible header v1; responses use correlation header v0.
  IDs advance once I/O starts and wrap from INT32_MAX to 1.
- Request and response frame bodies are capped at 1 MiB; the four-byte network
  length prefix is additional. A value of 1 MiB cannot fit with Kafka overhead.
- Fetch request limits may be exceeded by Kafka's first complete record batch.
  The client's hard cap still rejects an oversized frame. This was measured,
  not inferred solely from the request's fetch limit.
- Magic-2 uncompressed data only. Legacy magic-0/1, gzip/Snappy/LZ4/Zstd fail.
  Consumer recognizes broker offsets/leader epochs in batches, gaps,
  LogAppendTime, control-marker validation/suppression and delete-horizon flag.
  Reading epoch metadata does not implement protocol leader-epoch fencing.
- Isolation level=0. Aborted transaction payloads can be delivered; parsing
  last-stable-offset and aborted-transaction fields is not read-committed filtering.
- TransactionalId is null, ProducerId/epoch/sequence=-1. Magic-2's ability to carry
  these fields is not an idempotent or transactional Producer implementation.
- Compact fields and tag skipping in `protocol.s` are primitives only; no flexible
  request dispatch, response header adaptation or full flexible API support exists.

## Reference checks and remaining protocol risks

Version-sensitive layout checks used Apache's pinned
[ProduceRequest](https://github.com/apache/kafka/blob/3.9.1/clients/src/main/resources/common/message/ProduceRequest.json),
[FetchResponse](https://github.com/apache/kafka/blob/3.9.1/clients/src/main/resources/common/message/FetchResponse.json),
[JoinGroupResponse](https://github.com/apache/kafka/blob/3.9.1/clients/src/main/resources/common/message/JoinGroupResponse.json),
[OffsetFetchResponse](https://github.com/apache/kafka/blob/3.9.1/clients/src/main/resources/common/message/OffsetFetchResponse.json),
[ListOffsetsResponse](https://github.com/apache/kafka/blob/3.9.1/clients/src/main/resources/common/message/ListOffsetsResponse.json),
and [DefaultRecordBatch](https://github.com/apache/kafka/blob/3.9.1/clients/src/main/java/org/apache/kafka/common/record/DefaultRecordBatch.java).
For example, OffsetFetch v2 has a top-level error but no throttle field;
ListOffsets v1 has a timestamp/single offset but no throttle; JoinGroup v2
includes throttle. The audited parsers match these selected layouts.

Remaining qualification is PARTIAL/P1: maximum member/topic/header/record counts,
CPU budgets under adversarial valid inputs, independent malformed response corpus
for every API, real ACL denial, real compressed/transactional interoperability,
log truncation after leader failure and newer broker versions. Existing valid-CRC
unit mutations and one broker version do not close these gaps. Add independent
protocol oracles and property/fault cases as the memory/reliability work proceeds.
No new protocol feature was implemented during this audit.
