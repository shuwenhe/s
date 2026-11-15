#!/usr/bin/env python3
"""Summarize completed native benchmark evidence; refuse incomplete/failed runs."""
import json
import pathlib
import sys

run = pathlib.Path(sys.argv[1])
rows = []
for label in ('seed', 'canonical', 'stage2', 'stage3', 'stage4'):
    for mode in ('single', 'batch'):
        base = run / label / f'measure-{mode}'
        samples = json.loads((base / 'samples.json').read_text())
        if samples['exit_code'] != 0:
            raise SystemExit(f'failed benchmark: {label}/{mode}')
        metrics = {}
        for line in (base / 'stdout.log').read_text().splitlines():
            if '=' in line:
                key, value = line.split('=', 1)
                if value.isdigit():
                    metrics[key] = int(value)
        if metrics.get('messages') != 8192 or len(samples['windows']) != 8:
            raise SystemExit(f'incomplete benchmark: {label}/{mode}')
        rows.append(dict(label=label, delivery=mode, **metrics,
                         wall_seconds=samples['wall_seconds'],
                         sampled_cpu_seconds=samples['last_cpu_seconds'],
                         sampled_cpu_percent=100 * samples['last_cpu_seconds'] / samples['wall_seconds'],
                         peak_sampled_rss_kib=samples['peak_sampled_rss_kib'],
                         first_window_rss_kib=samples['windows'][0]['rss_kib'],
                         final_window_rss_kib=samples['windows'][-1]['rss_kib']))
(run / 'performance-summary.json').write_text(json.dumps(rows, indent=2) + '\n')
print('| Compiler | Delivery limit | Records/s | Mean poll ms | Mean backlog latency ms | CPU % | Peak RSS MiB |')
print('| --- | ---: | ---: | ---: | ---: | ---: | ---: |')
for row in rows:
    print(f"| {row['label']} | {1 if row['delivery']=='single' else 128} | "
          f"{row['consumer_records_per_second']} | {row['mean_poll_latency_ns']/1e6:.2f} | "
          f"{row['mean_end_to_end_latency_ms']} | {row['sampled_cpu_percent']:.1f} | "
          f"{row['peak_sampled_rss_kib']/1024:.1f} |")
