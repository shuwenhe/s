# Consumer protocol and wire compatibility

Pinned schema authority: Apache Kafka 3.9.1 common/message request/response JSON.
Every connection negotiates ApiVersions. Unknown/unavailable selected versions
fail explicitly; no untested flexible-version fallback.

| API | Key | Version | Current status |
| --- | ---: | ---: | --- |
| ApiVersions | 18 | 0 | Existing / exercised |
| Metadata | 3 | 4 | Implemented / real tested |
| Fetch | 1 | 4 | Implemented / real tested |
| FindCoordinator | 10 | 1 | Implemented / real tested |
| JoinGroup | 11 | 2 | Implemented / real tested |
| SyncGroup | 14 | 1 | Implemented / real tested |
| Heartbeat | 12 | 1 | Implemented / real liveness tested |
| LeaveGroup | 13 | 1 | Implemented / real reconnect tested |
| OffsetCommit | 8 | 2 | Implemented / real tested |
| OffsetFetch | 9 | 2 | Implemented / real tested |
| ListOffsets | 2 | 1 | Implemented / real tested |
| DescribeGroups | 15 | 1 | Implemented / real tested |

Request header v1 and response header v0, one pending exchange per socket, checked
correlation and length, total monotonic request deadlines distinct from short poll
budgets. Consumer transport state persists partial writes, size header, body and
pending group RPCs across service/poll calls. No Producer transport weakening.

Request/response cap: 1 MiB. Fetch requests at most 768 KiB; Kafka may return an
oversized first batch, which remains an explicit bounds failure at the frame cap.
Decoder CRC work advances in 4096-byte chunks and record parsing in at most
32-record steps. No output before complete validation. Ordered broker batches may
contain compaction gaps and control records; overlapping batches are rejected.
Recognized bounded incomplete trailing Fetch batches are reported, never emitted
or committed. A truncated TCP frame remains a transport/protocol failure.

Ordinary retained records and validated control markers have distinct validation.
Control marker version/type/payload/producer state/count are checked before
suppression. Known delete-horizon flag is supported. Header names require valid UTF-8. Unknown codecs/attributes
are explicit errors, not skipped records. Read-uncommitted includes aborted
transactional data; transaction filtering/exactly-once is not provided.

Classic subscription/assignment wire version is 0. Range sorts member IDs and
partition IDs per topic and considers only subscribed members. Eager rebalance
revokes old assignments and delivery epochs before joining. No static membership,
cooperative-sticky/round-robin, regex subscription or KIP-848 consumer protocol.
