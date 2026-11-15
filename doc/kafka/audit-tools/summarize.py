from pathlib import Path
import json,csv,statistics,hashlib
root=Path('/root/shuwen/s');p=root/'.bootstrap/kafka-audit/audit-20261115'
labels=['seed','canonical','stage2','stage3','stage4']
rows=list(csv.DictReader((p/'acceptance-isolated/status.tsv').open(),delimiter='\t'))
edge=list(csv.DictReader((p/'edge/status.tsv').open(),delimiter='\t'))
commit=list(csv.DictReader((p/'commit-fault/status.tsv').open(),delimiter='\t'))
text='''
## Fresh execution and compiler compatibility ledger

All commands ran from `/root/shuwen/s` on 2026-11-15. Loopback execution required
socket-enabled tool execution: the initial sandboxed attempt was **BLOCKED** with
`java.net.SocketException: Operation not permitted`, preserved in
`E/acceptance.log` (exit 1). No Java installation was performed; existing repository
Corretto 17.0.21 and the checksum-verified Kafka 3.9.1 distribution were reused.

The next stock runner attempt was **FAIL** at `consumer-benchmark/payload_sim.s`
with duplicate `main.main` (exit 1, `E/acceptance-local.log`). A retained audit copy
of the builder selects `test/kafka/consumer-benchmark/main.s` instead of its glob;
the copied acceptance runner uses this builder and an explicit repository root.
No test assertions or production sources were changed. This is a qualified audit
run, not a claim that the unchanged stock command passes.

| Compiler path | Compiler SHA256 | Build + run evidence | Fresh status |
| --- | --- | --- | --- |
'''
for label in labels:
 sha=(p/f'identity-{label}.sha256').read_text().split()[0]
 checks=[r for r in rows if r['label']==label]
 assert len(checks)==39 and all(r['exit']=='0' for r in checks)
 name='bin/s_seed' if label=='seed' else 'bin/s_compiler' if label=='canonical' else '.bootstrap/kafka-broker/phase1/selfhost/'+label
 text+=f'| {label}: `{name}` | `{sha}` | `E/acceptance-isolated/{label}/build-*.log`, executables and logs; 39/39 status rows exit 0 | PASS |\n'
text+='''
39 rows per path include eight build checks and 31 executable/scenario/measurement
checks. Each path was invoked independently on the current Kafka sources;
canonical and Stage2/3/4 are byte-identical compiler binaries, so these are five
execution paths, not five independent code generators. No requested stage was
unavailable. Compiler file identities are also recorded by `file` in
`E/identity-*.txt`. Fresh Kafka builds are not fresh compiler-bootstrap convergence.
A full compiler regression recipe was not rerun in this audit; the previously
reported eight baseline failures are not silently reclassified.

| Suite | Command / evidence | Result |
| --- | --- | --- |
| Consumer full matrix | `bash E/acceptance-audit.sh E/acceptance-isolated`; `acceptance-isolated.exit`, `status.tsv`, per-label logs/binaries and source-integrity checks | PASS; process exit 0; 195/195 status rows exit 0 |
| Commit response faults | `bash misc/scripts/check-kafka-consumer-commit-faults.sh E/commit-fault`; `E/commit-fault/status.tsv` | PASS; all 20 cases exit 0 (lost response/timeout/partial/auth × five paths); native peer fixtures, not real ACL broker tests |
| Real edge scenarios | `bash misc/scripts/check-kafka-consumer-edge.sh E/edge`; `E/edge.exit`, `status.tsv` | PASS; five paths × nine recorded checks; intentional SIGKILL checks exit 137, other checks exit 0 |
| Producer unit/fault and broker unit/TCP faults | `bash E/check-kafka-{producer,broker}-faults.sh COMPILER LABEL`; `E/regression-status.tsv`, per-suite logs | PASS under Seed and canonical, each suite exit 0; controlled native peers |
| Producer real + official consumer oracle | `bash E/check-kafka-producer-real.sh`; `E/producer-real.log`, `E/producer-real/oracle-{native,seed}.log` and exact consumed byte files | PASS Seed/canonical; independent oracle checks 11 records per path, plus benchmarks |
| Broker ApiVersions real | `bash E/check-kafka-broker-real.sh COMPILER LABEL`; `E/broker-real-{seed,canonical}.log` | PASS under both compilers; suite exit 0 |
| Internal behavior probes | `bash E/probe-run.sh`; `E/probe-status.tsv`, `probe-*.log` and executables | PASS as reproductions under all five paths; observed behaviors are findings, not fixes |
| RSS size sweep | `bash E/memory-run.sh`; `E/memory-status.tsv`, per-process `/proc` samples and logs | See memory report; 1 MiB rejection is measured unsupported behavior, not successful consumption |

Copied Producer/broker runners change only output directories and repository-root
resolution, so existing historical evidence paths are not overwritten. Their exact
text is retained in E, along with `regression-run.sh` that serializes shared fault
and broker ports. Current source hashes are in `E/source.sha256`; final
verification checks those against disk. The initial diagnostic parser/void-tail
compiler failures are retained in the attempt/build archives and are not called
Kafka test failures. The implementation code was not changed to make probes pass.

The edge runner retries broker ISR restoration using assertions; intermediate
`AssertionError` lines in its logs are not individual PASS claims. Its final exit,
all scenario rows and successful broker restoration govern the suite result.
Neither successful edge checks nor peer fixtures prove real ACL behavior.

## Measured performance (finite backlog workload)

| Compiler | Single-delivery records/s | Batch-delivery records/s | Single mean poll ms | Batch mean poll ms | Peak native RSS single / batch MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
'''
for label in labels:
 d=[]
 for style in ['single','batch']:
  fields=dict(x.split('=',1) for x in (p/f'acceptance-isolated/{label}/benchmark-{style}.log').read_text().splitlines() if '=' in x)
  sm=json.loads((p/f'acceptance-isolated/{label}/measure-{style}/samples.json').read_text())
  d.append((int(fields['consumer_records_per_second']),int(fields['mean_poll_latency_ns'])/1e6,sm['peak_sampled_rss_kib']/1024))
 text+=f'| {label} | {d[0][0]} | {d[1][0]} | {d[0][1]:.3f} | {d[1][1]:.3f} | {d[0][2]:.1f} / {d[1][2]:.1f} |\n'
text+='''
Method: 8,192 records × 256-byte values, one topic/partition, Producer preload in
64-record ACK=1 batches, requested Fetch max=16 KiB, application delivery limit
1 or 128 (actual native record batches contain 64). Production finishes before
the timed drain. Same native process includes Producer allocations; process RSS
is sampled every 20 ms by the repository measure.py, with GNU time family
resources separately. No warmup; other audit jobs share the host. Larger batch
poll latency reflects more records/work per call and is not per-record latency.
End-to-end latency includes preload/backlog residence. These are not steady-state,
maximum sustainable throughput, CPU-isolated results, a multi-partition scale
claim, or a matched external-client comparison. Resource files and samples retain
CPU seconds, wall time and window memory for reanalysis.
'''
f=root/'doc/kafka/KAFKA_CAPABILITY_MATRIX.md';s=f.read_text();marker='\n## Fresh execution and compiler compatibility ledger\n';s=s.split(marker)[0]+text;f.write_text(s)
# Precise checkpoint summary. The 100 ms checkpoints permit a post-event sample.
result=[]
for file in sorted(p.glob('memory-*/samples.json')):
 data=json.loads(file.read_text());samples=data['samples'];events=[]
 for event in data['events']:
  if not event['text'].startswith('phase='):continue
  later=next((r for r in samples if r['seconds']>=event['seconds']+.03),event.get('sample',{}))
  events.append({'text':event['text'],'seconds':event['seconds'],'rss_kib':later.get('VmRSS'),'anon_kib':later.get('RssAnon'),'fd_count':later.get('fd_count')})
 row={'case':file.parent.name,'exit':data['exit'],'wall_seconds':data['wall_seconds'],'sample_count':len(samples),'peak_sampled_rss_kib':data['peak_rss_kib'],'peak_status_hwm_kib':max((r.get('VmHWM',0) for r in samples),default=0),'events':events}
 result.append(row)
(p/'memory-checkpoints.json').write_text(json.dumps(result,indent=2)+'\n')
