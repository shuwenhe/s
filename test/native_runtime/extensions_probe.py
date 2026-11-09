"""Compile and exercise the native extension implementation without the compiler."""
from pathlib import Path
import subprocess, tempfile, socket, threading, json
root=Path(__file__).resolve().parents[2]
source=root/'src/cmd/compile/internal/codegen/native_runtime_extensions.c'
assert source.exists(), 'missing native runtime extensions'
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp)
 harness=r'''
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
typedef long I; typedef struct { I n; unsigned char p[]; } S;
void *alloc(I n) __asm__(".Ls_native_alloc"); void *alloc(I n){return calloc(1,n);}
char *toc(S *s) __asm__(".Ls_native_to_c"); char *toc(S*s){char*p=calloc(1,s->n+1);memcpy(p,s->p,s->n);return p;}
S *readfile(S*) __asm__(".Ls_native_read_file"); S*readfile(S*s){FILE*f=fopen(toc(s),"rb");if(!f)return 0;fseek(f,0,2);I n=ftell(f);rewind(f);S*r=alloc(n+8);r->n=n;fread(r->p,1,n,f);fclose(f);return r;}
I run(I*) __asm__(".Ls_native_run_argv"); I run(I*a){fputs("captured stdout",stdout);fflush(stdout);return a[0];}
void *envptr __asm__(".Ls_native_envp");
extern S*s_ext_capture(I*); extern I s_ext_socket(I,I,I),s_ext_connect(I,S*,I,I),s_ext_close(I),s_ext_env_exists(S*);
extern I *s_ext_read_binary(S*),*s_ext_read_range(S*,I,I); extern I s_ext_write_binary(S*,I*),s_ext_exists(S*); extern S*s_ext_read(I,I); extern I s_ext_write(I,S*);
S*str(char*x){S*s=alloc(strlen(x)+8);s->n=strlen(x);memcpy(s->p,x,s->n);return s;}
int main(int argc,char**argv){S*p=str(argv[1]);I a[]={4,0,128,255,65};if(s_ext_write_binary(p,a))return 1;I*b=s_ext_read_binary(p);if(!b||b[0]!=4||b[2]!=128||b[3]!=255)return 2;I*c=s_ext_read_range(p,1,2);if(!c||c[0]!=2||c[1]!=128||c[2]!=255)return 3;if(!s_ext_exists(p)||s_ext_exists(str("/definitely/missing")))return 4;if(s_ext_read_range(p,-1,2))return 5;I args[]={0};S*out=s_ext_capture(args);if(!out||out->n!=15||memcmp(out->p,"captured stdout",15))return 6;args[0]=3;if(s_ext_capture(args))return 7;char*env[]={"EMPTY=","KEY=value",0};envptr=env;if(!s_ext_env_exists(str("EMPTY"))||s_ext_env_exists(str("KE")))return 8;I fd=s_ext_socket(2,1,0);if(fd<0||s_ext_connect(fd,str("127.0.0.1"),atol(argv[2]),2))return 9;if(s_ext_write(fd,str("ping"))!=4)return 10;S*reply=s_ext_read(fd,4);if(!reply||reply->n!=4||memcmp(reply->p,"pong",4))return 11;s_ext_close(fd);puts("native binary/range/existence/environment/capture/loopback probes passed");}
'''
 (p/'probe.c').write_text(harness)
 subprocess.run(['gcc','-S','-O1','-fno-pie',str(p/'probe.c'),'-o',str(p/'harness.s')],check=True)
 encoded=(source.with_suffix('.s')).read_text().split('func amd64_native_extensions_runtime() string {',1)[1]
 assembly=''.join(json.loads(line.strip().removeprefix('+ ')) for line in encoded.splitlines() if line.strip().startswith('+ '))
 (p/'combined.s').write_text((p/'harness.s').read_text()+'\n'+assembly)
 subprocess.run(['gcc','-no-pie',str(p/'combined.s'),'-o',str(p/'probe')],check=True)
 server=socket.socket(); server.bind(('127.0.0.1',0)); server.listen()
 def respond():
  conn,_=server.accept()
  with conn:
   assert conn.recv(4)==b'ping'
   conn.sendall(b'pong')
 worker=threading.Thread(target=respond,daemon=True); worker.start()
 subprocess.run([str(p/'probe'),str(p/'bytes'),str(server.getsockname()[1])],check=True,timeout=10)
 worker.join(timeout=2); server.close()
