import json,os,pathlib,selectors,subprocess,sys,time
out=pathlib.Path(sys.argv[1]); out.mkdir()
p=subprocess.Popen(sys.argv[2:],stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
s=selectors.DefaultSelector();s.register(p.stdout,selectors.EVENT_READ)
start=time.monotonic();samples=[];events=[];pending=b'';phase='startup';last=0
with (out/'stdout.log').open('wb') as log:
 while True:
  now=time.monotonic()-start
  row={'seconds':now,'phase':phase}
  try:
   status=pathlib.Path(f'/proc/{p.pid}/status').read_text()
   for line in status.splitlines():
    if line.startswith(('VmRSS:','VmHWM:','VmSize:','RssAnon:','RssFile:')): k,v,*_=line.split();row[k.rstrip(':')]=int(v)
   stat=pathlib.Path(f'/proc/{p.pid}/stat').read_text().rsplit(')',1)[1].split()
   row['cpu_seconds']=(int(stat[11])+int(stat[12]))/os.sysconf('SC_CLK_TCK')
   row['fd_count']=len(list(pathlib.Path(f'/proc/{p.pid}/fd').iterdir()))
   if now-last>=10:
    last=now
    try: (out/f'smaps-{int(now):04}.txt').write_text(pathlib.Path(f'/proc/{p.pid}/smaps_rollup').read_text())
    except (OSError,PermissionError): pass
   if 'VmRSS' in row: samples.append(row)
  except (OSError,ValueError): pass
  for key,_ in s.select(.05):
   data=os.read(key.fd,65536)
   if data:
    log.write(data);log.flush();pending+=data
    while b'\n' in pending:
     line,pending=pending.split(b'\n',1);line=line.decode(errors='replace')
     events.append({'seconds':time.monotonic()-start,'text':line,'sample':row})
     if line.startswith('phase='): phase=line.split()[0][6:]
   else: s.unregister(key.fileobj)
  if p.poll() is not None: break
  if now>2000 or row.get('VmRSS',0)>1800000:
   p.kill();events.append({'text':'audit resource/time guard killed child','seconds':now});break
 code=p.wait()
summary={'command':sys.argv[2:],'pid':p.pid,'exit':code,'wall_seconds':time.monotonic()-start,'samples':samples,'events':events,'peak_rss_kib':max((r['VmRSS'] for r in samples),default=None)}
(out/'samples.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps({k:v for k,v in summary.items() if k not in ('samples','events')}),flush=True)
sys.exit(code if code>=0 else 128-code)
