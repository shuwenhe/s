#!/usr/bin/env python3
"""Native-client TCP peers, not real Kafka. Requests checked independently."""
import argparse,json,pathlib,socket,struct,subprocess,threading,time,traceback
parser=argparse.ArgumentParser();parser.add_argument('client');parser.add_argument('output');parser.add_argument('--modes',default='normal,fin,rst,lost-response,coordinator-loss,expired,timeout,auth,malformed,unavailable,cleanup');a=parser.parse_args()
out=pathlib.Path(a.output);out.mkdir(parents=True,exist_ok=False)
def exact(c,n):
 b=b''
 while len(b)<n:
  d=c.recv(n-len(b))
  if not d:raise EOFError('peer EOF')
  b+=d
 return b
def frame(c):
 n=struct.unpack('>i',exact(c,4))[0];assert 10<=n<=1048576,n
 b=exact(c,n);key,version,correlation=struct.unpack('>hhi',b[:8]);return key,version,correlation,b
def response(c,corr,body):
 b=struct.pack('>i',corr)+body;c.sendall(struct.pack('>i',len(b))+b)
def text(s):
 b=s.encode();return struct.pack('>h',len(b))+b
rows=[]
for mode in a.modes.split(','):
 stop=threading.Event();events=[];failures=[];threads=[];listeners=[];sockets=[]
 def serve(port):
  listener=socket.socket();listener.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1);listener.bind(('127.0.0.1',port));listener.listen();listener.settimeout(.1);listeners.append(listener)
  def run():
   first=True
   try:
    while not stop.is_set():
     try:c,_=listener.accept()
     except socket.timeout:continue
     sockets.append(c);c.settimeout(2)
     try:
      key,version,corr,b=frame(c);assert (key,version)==(18,0),(key,version)
      versions=struct.pack('>hi',0,3)+struct.pack('>hhh',13,1,1)+struct.pack('>hhh',10,1,1)+struct.pack('>hhh',18,0,0)
      response(c,corr,versions);events.append({'port':port,'api':18})
      if first and port==19092 and mode in ('fin','rst','coordinator-loss'):
       time.sleep(.05)
       if mode=='rst':c.setsockopt(socket.SOL_SOCKET,socket.SO_LINGER,struct.pack('ii',1,0))
       else:c.shutdown(socket.SHUT_WR)
       c.close();first=False
       if mode=='coordinator-loss':listener.close();return
       continue
      key,version,corr,b=frame(c);events.append({'port':port,'api':key,'version':version})
      if key==10:
       assert version==1
       response(c,corr,struct.pack('>ihh',0,0,-1)+struct.pack('>i',1)+text('127.0.0.1')+struct.pack('>i',19093))
       key,version,corr,b=frame(c);events.append({'port':port,'api':key,'version':version})
      assert (key,version)==(13,1),(key,version)
      assert b.endswith(text('close-group')+text('close-member')),b
      if mode=='lost-response' and first:c.shutdown(socket.SHUT_WR);c.close();first=False;continue
      if mode=='timeout':time.sleep(.8);c.close();continue
      status=25 if mode in ('expired','lost-response') else 30 if mode=='auth' else 0
      body=struct.pack('>ih',0,status)
      if mode=='malformed':body=b'\x00'
      response(c,corr,body);c.close();first=False
     except (EOFError,ConnectionResetError,BrokenPipeError,socket.timeout):c.close()
   except Exception:failures.append(traceback.format_exc())
  t=threading.Thread(target=run,daemon=True);threads.append(t);t.start()
 if mode not in ('unavailable','cleanup'):
  serve(19092)
  if mode=='coordinator-loss':serve(19093)
 start=time.monotonic();r=subprocess.run([a.client,mode],capture_output=True,text=True,timeout=5);elapsed=time.monotonic()-start
 stop.set()
 for t in threads:t.join(1)
 for s in sockets+listeners:
  try:s.close()
  except OSError:pass
 (out/f'{mode}.log').write_text(r.stdout+r.stderr)
 (out/f'{mode}-peer.json').write_text(json.dumps({'events':events,'failures':failures},indent=2)+'\n')
 rows.append({'mode':mode,'exit':r.returncode,'seconds':elapsed,'peer_errors':len(failures)});print(mode,r.returncode,flush=True)
(out/'status.json').write_text(json.dumps(rows,indent=2)+'\n')
raise SystemExit(1 if any(r['exit'] or r['peer_errors'] for r in rows) else 0)
