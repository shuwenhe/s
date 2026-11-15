#!/usr/bin/env python3
"""Run a native workload and retain sampled process RSS/CPU and stdout evidence."""
import json, os, pathlib, selectors, subprocess, sys, time
out=pathlib.Path(sys.argv[1]); out.mkdir(parents=True,exist_ok=True)
process=subprocess.Popen(sys.argv[2:], stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
selector=selectors.DefaultSelector(); selector.register(process.stdout, selectors.EVENT_READ)
rows=[]; windows=[]; partial=b''; started=time.monotonic()
with (out/'stdout.log').open('xb') as log:
    while True:
        rss=None; cpu=None
        try:
            fields=pathlib.Path(f'/proc/{process.pid}/stat').read_text().rsplit(')',1)[1].split()
            ticks=os.sysconf('SC_CLK_TCK'); cpu=(int(fields[11])+int(fields[12]))/ticks
            status=pathlib.Path(f'/proc/{process.pid}/status').read_text()
            rss=int(next(line for line in status.splitlines() if line.startswith('VmRSS:')).split()[1])
            rows.append({'seconds':time.monotonic()-started,'rss_kib':rss,'cpu_seconds':cpu})
        except (FileNotFoundError,ProcessLookupError,StopIteration): pass
        for key,_ in selector.select(0.02):
            chunk=os.read(key.fd,65536)
            if chunk:
                log.write(chunk);log.flush();sys.stdout.buffer.write(chunk);sys.stdout.buffer.flush();partial+=chunk
                while b'\n' in partial:
                    line,partial=partial.split(b'\n',1)
                    if line.startswith(b'window_records='):windows.append({'records':int(line.split(b'=')[1]),'rss_kib':rss,'cpu_seconds':cpu,'seconds':time.monotonic()-started})
        if process.poll() is not None:
            rest=process.stdout.read()
            if rest:log.write(rest);sys.stdout.buffer.write(rest);sys.stdout.buffer.flush()
            break
        if time.monotonic()-started>150:
            process.kill();process.wait();raise RuntimeError('native benchmark timeout')
elapsed=time.monotonic()-started
summary={'exit_code':process.returncode,'wall_seconds':elapsed,'sample_count':len(rows),'peak_sampled_rss_kib':max((r['rss_kib'] for r in rows),default=None),'last_cpu_seconds':rows[-1]['cpu_seconds'] if rows else None,'windows':windows,'samples':rows}
(out/'samples.json').write_text(json.dumps(summary,indent=2)+'\n')
raise SystemExit(process.returncode)
