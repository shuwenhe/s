from pathlib import Path
import json,statistics,math,csv
root=Path('/root/shuwen/s');p=root/'.bootstrap/kafka-audit/audit-20261115'
d=json.loads((p/'memory-sustained/samples.json').read_text());rows=d['samples'];events=d['events']
assert d['exit']==13 and d['wall_seconds']>=1800
points=[e for e in events if e['text'].startswith('phase=')]
count=int(next(e['text'].split('count=')[1] for e in events if e['text'].startswith('phase=before-cleanup')))
late=[r for r in rows if 1200<=r['seconds']<=1800]
xs=[r['seconds']/60 for r in late];ys=[r['VmRSS']/1024 for r in late];xm=statistics.mean(xs);ym=statistics.mean(ys)
slope=sum((x-xm)*(y-ym) for x,y in zip(xs,ys))/sum((x-xm)**2 for x in xs)
def at(phase):
 e=next((e for e in events if e['text'].startswith('phase='+phase+' ')),None)
 if e is None:return {}
 return next((r for r in rows if r['seconds']>=e['seconds']+.03),e.get('sample',{}))
s='''
### Completed 30-minute canonical run

Status **PARTIAL for sustained consumption/RSS measurement; FAIL for final close**.
The native process ran for
'''+f"""{d['wall_seconds']:.2f} seconds, with {count} complete 1 KiB replay deliveries,\nACKs and commit calls, and one deliberate session-loss/rejoin cycle. The 1800-second\ncondition is measured inside the native loop, not inferred from a timeout or\nbroker uptime. Process exit was **13**, the harness branch for a nonzero
`consumer_close` result. It completed the timed consumption loop but did not
emit closed/reset/idle checkpoints. No sustained clean-shutdown PASS is claimed. `E/memory-sustained/samples.json` contains\n{len(rows):,} samples.\n\n"""
s+='| Checkpoint | Native RSS KiB | Anonymous KiB | FD count |\n| --- | ---: | ---: | ---: |\n'
for phase in ['initial','delivered','ack','commit','revoked','rejoined','before-cleanup','closed','cleanup','idle-after-cleanup']:
 r=at(phase);s+=f"| {phase} | {r.get('VmRSS','—')} | {r.get('RssAnon','—')} | {r.get('fd_count','—')} |\n"
s+=f"\nPeak sampled RSS: **{d['peak_rss_kib']:,} KiB ({d['peak_rss_kib']/1024:.2f} MiB)**.\nLast sampled native CPU time: {rows[-1]['cpu_seconds']:.2f} seconds.\nFinal ten-minute sampled RSS range: **{min(ys):.2f}–{max(ys):.2f} MiB**;\nleast-squares slope **{slope:.4f} MiB/minute** over those samples.\n\n"
s+='| Elapsed consumption window | Samples | RSS min MiB | RSS mean MiB | RSS max MiB |\n| --- | ---: | ---: | ---: | ---: |\n'
for start in range(0,1800,300):
 values=[r['VmRSS']/1024 for r in rows if start<=r['seconds']<start+300]
 s+=f'| {start//60}–{start//60+5} min | {len(values)} | {min(values):.2f} | {statistics.mean(values):.2f} | {max(values):.2f} |\n'
s+='''
Interpretation: the final-window measurements must be read as a finite observed
trend, not a zero-growth guarantee or proof of leak freedom. This low-rate replay
keeps input size and broker backlog fixed, repeatedly exercising Fetch/decode,
seek, ACK and commit. It does not exercise a continuous independent input stream,
many partitions, many members, sustained 512 KiB records, or 30 minutes under Seed.
The Seed size sweep and allocator source already establish a separate retention
problem; the canonical experiment cannot clear that finding. Follow-up acceptance
must use fresh data and agreed deployment load/limits across compiler paths.

![Native Consumer RSS size/replay and sustained measurements](KAFKA_MEMORY_RSS.png)

Standalone [PDF figure](KAFKA_MEMORY_RSS.pdf). Raw data: per-case `samples.json`,
`E/memory-checkpoints.json`, `E/rss-sustained.csv` and ten-second `smaps-*.txt`.
Post-close FD/RSS for the sustained run are unavailable because the harness
returned immediately on close failure; table dashes mean unmeasured. Short size
cases did measure close/reset. The close call's detailed returned error was not
logged by this harness, so its cause remains unresolved (R-02). The enclosing
runner exits 0 after recording child exit 13; its wrapper status must not override
`memory-status.tsv` or the child's samples. A repeat needs explicit close error
code/native code/message and membership/heartbeat state logging.

## Remaining work and recommended next action

Prioritize M-01 allocation/lifetime correctness, then M-02 transient-reference
cleanup and C-03 bounded decoding. Keep the current reproduction as a baseline.
Instrument allocation counts/live bytes and compare transport-only, decoder-only,
empty-poll, commit and rebalance workloads before selecting a fix. A local bounded
byte-buffer/ownership design and Seed runtime reclamation have different scope;
neither should be replaced by raising caps or assuming ACK frees the heap.

**Not executed in this audit:** thirty minutes for each payload/compiler pair;
continuous newly produced traffic; RSS after independent multi-member rebalance;
forced-GC/live-object accounting; maximum-count adversarial memory/latency tests;
and host-isolated steady-state comparisons. These are PARTIAL qualification gaps,
not tests claimed PASS. No unavailable compiler path was silently skipped.
'''
f=root/'doc/kafka/KAFKA_MEMORY_AUDIT.md';body=f.read_text();body=body.split('\n### Completed 30-minute canonical run\n')[0]+s;f.write_text(body)
(p/'memory-long-summary.json').write_text(json.dumps({'exit':d['exit'],'wall_seconds':d['wall_seconds'],'deliveries':count,'sample_count':len(rows),'peak_rss_kib':d['peak_rss_kib'],'late_min_mib':min(ys),'late_max_mib':max(ys),'late_slope_mib_per_minute':slope,'final_rss_kib':at('before-cleanup').get('VmRSS')},indent=2)+'\n')
print((p/'memory-long-summary.json').read_text())
