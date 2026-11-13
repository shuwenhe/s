import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { createServer, type Server } from 'node:http';
import { GET, POST } from '../app/api/users/route.ts';
import { GET as userGET, PUT, DELETE } from '../app/api/users/[id]/route.ts';
let server: Server;
let origin: string;
let calls = 0;
before(async () => {
 server = createServer(async (req,res) => {
  calls++;
  let body = ''; for await (const chunk of req) body += chunk;
  if (req.url === '/api/users/oversized') { res.end('x'.repeat(1048577)); return; }
  if (req.url === '/api/users/method') { res.writeHead(405,{'content-type':'application/json',allow:'GET, HEAD, PUT, DELETE','x-upstream-secret':'private'}); res.end(JSON.stringify({error:{code:'method',message:'method not allowed'}})); return; }
  if (req.url === '/api/users/redirect') { res.writeHead(302,{location:'http://example.com/'}); res.end(); return; }
  if (req.method === 'DELETE') { res.writeHead(204); res.end(); return; }
  if (req.url === '/api/users/missing') { res.writeHead(404,{'content-type':'application/json'}); res.end(JSON.stringify({error:{code:'not_found',message:'No user'}})); return; }
  res.writeHead(req.method === 'POST' ? 201 : 200, {'content-type':'application/json'});
  res.end(JSON.stringify({method:req.method,path:req.url,body,contentType:req.headers['content-type'] ?? null}));
 });
 await new Promise<void>(resolve => server.listen(0,'127.0.0.1',resolve));
 const address = server.address(); assert.ok(address && typeof address !== 'string');
 origin = `http://127.0.0.1:${address.port}`; process.env.S_API_ORIGIN = origin;
});
after(async () => { await new Promise<void>((resolve,reject)=>server.close(err=>err?reject(err):resolve())); });
const context = (id:string) => ({params:Promise.resolve({id})});
test('collection GET keeps query data on the configured upstream origin',async()=>{
 const r=await GET(new Request('http://localhost/api/users?q=%E4%B8%AD&limit=101&url=http%3A%2F%2Fevil.invalid')); assert.equal(r.status,200);
 assert.equal((await r.json()).path,'/api/users?q=%E4%B8%AD&limit=101&url=http%3A%2F%2Fevil.invalid');
});
test('POST streams JSON bytes to the S server and preserves status',async()=>{
 const r=await POST(new Request('http://localhost/api/users',{method:'POST',body:'{"name":"Ada"}',headers:{'content-type':'application/json'}}));
 assert.equal(r.status,201); assert.equal((await r.json()).body,'{"name":"Ada"}');
});
test('item GET and PUT preserve identity and errors; DELETE returns empty 204',async()=>{
 const r=await userGET(new Request('http://localhost/'),context('missing')); assert.equal(r.status,404); assert.equal((await r.json()).error.code,'not_found');
 const update=await PUT(new Request('http://localhost/',{method:'PUT',body:'{}'}),context('123')); assert.equal((await update.json()).path,'/api/users/123');
 const deleted=await DELETE(new Request('http://localhost/',{method:'DELETE'}),context('123')); assert.equal(deleted.status,204); assert.equal(await deleted.text(),'');
});
test('oversized bodies are rejected before contacting upstream, including streams',async()=>{
 const prior=calls;
 const request = new Request('http://localhost/',{method:'POST',body:'x'.repeat(65537)});
 const r=await POST(request); assert.equal(r.status,413); assert.equal(calls,prior);
});
test('oversized upstream output and redirects become bounded JSON errors',async()=>{
 for(const id of ['oversized','redirect']) { const r=await userGET(new Request('http://localhost/'),context(id)); assert.equal(r.status,502); assert.ok((await r.json()).error.message); }
});
test('untrusted IDs cannot change path or origin',async()=>{
 const prior=calls; const r=await userGET(new Request('http://localhost/'),context('../users')); assert.equal(r.status,400); assert.equal(calls,prior);
});

test('unsupported API methods return consistent JSON 405 errors and Allow', async () => {
 const collection = await import('../app/api/users/route.ts');
 const item = await import('../app/api/users/[id]/route.ts');
 for (const [routes, methods, allow] of [[collection, ['PUT','DELETE','PATCH','OPTIONS'], 'GET, HEAD, POST'], [item, ['POST','PATCH','OPTIONS'], 'GET, HEAD, PUT, DELETE']] as const) {
  for (const method of methods) {
   const handler = (routes as unknown as Record<string, (request: Request) => Promise<Response> | Response>)[method];
   assert.equal(typeof handler, 'function', `${method} handler missing`);
   const response = await handler(new Request('http://localhost/api/users', {method}));
   assert.equal(response.status,405);
   assert.equal(response.headers.get('allow'),allow);
   assert.deepEqual(await response.json(),{error:{code:'method',message:'method not allowed'}});
  }
 }
});

test('HEAD preserves GET status and byte length while omitting the body', async () => {
 const collection = await import('../app/api/users/route.ts');
 const item = await import('../app/api/users/[id]/route.ts');
 const collectionHEAD = (collection as unknown as {HEAD:(r:Request)=>Promise<Response>}).HEAD;
 const itemHEAD = (item as unknown as {HEAD:(r:Request,c:ReturnType<typeof context>)=>Promise<Response>}).HEAD;
 assert.equal(typeof collectionHEAD,'function'); assert.equal(typeof itemHEAD,'function');
 for (const response of [await collectionHEAD(new Request('http://localhost/api/users',{method:'HEAD'})), await itemHEAD(new Request('http://localhost/api/users/missing',{method:'HEAD'}), context('missing'))]) {
  assert.ok([200,404].includes(response.status));
  assert.equal(await response.text(),'');
  assert.ok(Number(response.headers.get('content-length')) > 0);
 }
});

test('POST and PUT forward Content-Type so S can enforce media-type rules', async () => {
 for (const [method, handler] of [['POST', (r:Request)=>POST(r)], ['PUT', (r:Request)=>PUT(r,context('123'))]] as const) {
  const response = await handler(new Request('http://localhost/api/users',{method,body:'{}',headers:{'content-type':'text/plain'}}));
  assert.equal((await response.json()).contentType,'text/plain');
 }
 const request = new Request('http://localhost/api/users',{method:'POST',body:new Uint8Array([123,125])});
 const response = await POST(request);
 assert.equal((await response.json()).contentType,null);
});
test('safe upstream Allow is forwarded without unrelated upstream headers', async () => {
 const response = await userGET(new Request('http://localhost/api/users/method'),context('method'));
 assert.equal(response.status,405);
 assert.equal(response.headers.get('allow'),'GET, HEAD, PUT, DELETE');
 assert.equal(response.headers.get('x-upstream-secret'),null);
});
