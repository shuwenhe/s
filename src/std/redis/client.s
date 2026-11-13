package std.redis
import ("std.tcp"
 "std.tls"
 "std.time")
struct connection {
 std.tcp.socket socket
 std.tls.session secure
 bool use_tls
 bool closed
 bool in_multi
 bool watched
 bool busy
 int read_timeout_ms
 int write_timeout_ms
 limits bounds
 string buffered
 int last_reply_bytes
}
func close(connection* c) error {
 if c.closed { return error {} }
 c.closed=true
 c.buffered=""
 c.in_multi=false
 c.watched=false
 tls_code := 0
 if c.use_tls { tls_code=std.tls.close(c.secure*).code }
 tcp_code := std.tcp.close(c.socket*).code
 if tls_code != 0 { return error {code:error_transport,native_code:tls_code,message:"TLS close failed",fatal:true} }
 if tcp_code != 0 { return error {code:error_transport,native_code:tcp_code,message:"TCP close failed",fatal:true} }
 return error {}
}
func _redis_fatal(connection* c, int code, int native_code, string message) error {
 close(c*)
 return error {code:code,native_code:native_code,message:message,fatal:true}
}
func _redis_io_error(connection* c, int native_code) error {
 code := error_transport
 if native_code == 110 { code=error_timeout }
 return _redis_fatal(c*,code,native_code,"Redis transport failed")
}
func _redis_deadline(int milliseconds) (int,error) {
 now,e := std.time.monotonic_clock()
 if e.code != 0 { return 0,error {code:error_transport,native_code:e.code,message:"monotonic clock failed"} }
 return now+milliseconds*1000000,error {}
}
func _redis_remaining(int deadline) (int,error) {
 now,e := std.time.monotonic_clock()
 if e.code != 0 { return 0,error {code:error_transport,native_code:e.code,message:"monotonic clock failed"} }
 if now >= deadline { return 0,_redis_error(error_timeout,"Redis deadline expired") }
 return (deadline-now+999999)/1000000,error {}
}
func _redis_write(connection* c, string data) error {
 timeout := c.write_timeout_ms
 if c.use_tls {
  count,e := std.tls.write_all(c.secure*,data,timeout)
  if e.code != 0 { return _redis_io_error(c*,e.code) }
  if count != len(data) { return _redis_fatal(c*,error_transport,0,"short TLS write") }
 } else {
  count,e := std.tcp.write_all(c.socket*,data,timeout)
  if e.code != 0 { return _redis_io_error(c*,e.code) }
  if count != len(data) { return _redis_fatal(c*,error_transport,0,"short TCP write") }
 }
 return error {}
}
func _redis_read(connection* c, int deadline) (document,error) {
 p := new_decoder(c.bounds)
 feed(p*,c.buffered)
 c.buffered=""
 while true {
  advance(p*)
  if p.failure.code != 0 { return document {},_redis_fatal(c*,p.failure.code,0,p.failure.message) }
  if p.complete {
   c.last_reply_bytes=p.position
   c.buffered=__string_slice(p.source,p.position,len(p.source))
   compact := document {nodes:make([]node,p.doc.count),count:p.doc.count}
   i := 0
   while i < compact.count { compact.nodes[i]=p.doc.nodes[i]
 i=i+1 }
   return compact,error {}
  }
  remaining,e := _redis_remaining(deadline)
  if e.code != 0 { return document {},_redis_fatal(c*,e.code,e.native_code,e.message) }
  chunk := std.tcp.read_chunk {}
  native_code := 0
  if c.use_tls {
   data,err := std.tls.read_some(c.secure,4096,remaining)
   chunk=data
 native_code=err.code
  } else {
   data,err := std.tcp.read_some(c.socket*,4096,remaining)
   chunk=data
 native_code=err.code
  }
  if native_code != 0 { return document {},_redis_io_error(c*,native_code) }
  if chunk.eof { return document {},_redis_fatal(c*,error_transport,0,"EOF before complete RESP reply") }
  if len(chunk.data) == 0 { return document {},_redis_fatal(c*,error_transport,0,"read made no progress") }
  feed(p*,chunk.data)
 }
 return document {},_redis_error(error_transport,"unreachable read")
}
func _redis_verb(string input) string {
 out := ""
 i := 0
 while i < len(input) {
  b := __host_byte_at(input,i)
  if b >= 97 && b <= 122 { b=b-32 }
  out=out+__std_byte_string(b)
 i=i+1
 }
 return out
}
func _redis_validate(string[] args) error {
 if len(args) == 0 { return _redis_error(error_invalid,"empty command") }
 if len(args[0]) == 0 || len(args[0]) > 64 { return _redis_error(error_bounds,"command name must be 1..64 bytes") }
 v := _redis_verb(args[0])
 if v == "SUBSCRIBE" || v == "PSUBSCRIBE" || v == "SSUBSCRIBE" || v == "UNSUBSCRIBE" || v == "PUNSUBSCRIBE" || v == "SUNSUBSCRIBE" || v == "MONITOR" || v == "HELLO" || v == "CLIENT" || v == "SYNC" || v == "PSYNC" || v == "REPLCONF" || v == "RESET" || v == "QUIT" || v == "SHUTDOWN" { return _redis_error(error_state,"stream-changing command unsupported") }
 return error {}
}
func _redis_exchange(connection* c, string[] args) (document,error) {
 if c.closed { return document {},_redis_error(error_closed,"Redis connection closed") }
 validation := _redis_validate(args)
 if validation.code != 0 { return document {},validation }
 wire,e := encode(args,c.bounds)
 if e.code != 0 { return document {},e }
 write_error := _redis_write(c*,wire)
 if write_error.code != 0 { return document {},write_error }
 deadline,de := _redis_deadline(c.read_timeout_ms)
 if de.code != 0 { return document {},_redis_fatal(c*,de.code,de.native_code,de.message) }
 reply,re := _redis_read(c*,deadline)
 if re.code != 0 { return reply,re }
 if len(c.buffered) != 0 { return reply,_redis_fatal(c*,error_protocol,0,"unsolicited Redis bytes") }
 verb := _redis_verb(args[0])
 root := reply.nodes[0]
 if verb == "EXEC" && c.in_multi { c.in_multi=false
 c.watched=false }
 if root.kind == "error" { return reply,error {code:error_server,message:root.text} }
 if verb == "MULTI" && root.kind == "simple" && root.text == "OK" { c.in_multi=true }
 if verb == "DISCARD" && root.kind == "simple" && root.text == "OK" { c.in_multi=false
 c.watched=false }
 if verb == "WATCH" && root.kind == "simple" && root.text == "OK" { c.watched=true }
 if verb == "UNWATCH" && root.kind == "simple" && root.text == "OK" { c.watched=false }
 return reply,error {}
}
func execute(connection* c, string[] args) (document,error) {
 if c.busy { return document {},_redis_error(error_state,"connection busy") }
 c.busy=true
 reply,e := _redis_exchange(c*,args)
 c.busy=false
 return reply,e
}
func connect(options source) (connection,error) {
 o := source
 if o.host == "" { o.host="127.0.0.1" }
 if o.port == 0 { o.port=6379 }
 if o.connect_timeout_ms == 0 { o.connect_timeout_ms=5000 }
 if o.read_timeout_ms == 0 { o.read_timeout_ms=5000 }
 if o.write_timeout_ms == 0 { o.write_timeout_ms=5000 }
 c := connection {closed:true}
 bounds,be := _redis_limits(o.bounds)
 if be.code != 0 { return c,be }
 if o.port < 1 || o.port > 65535 || o.database < 0 || o.connect_timeout_ms < 1 || o.read_timeout_ms < 1 || o.write_timeout_ms < 1 || o.connect_timeout_ms > 2147483647 || o.read_timeout_ms > 2147483647 || o.write_timeout_ms > 2147483647 { return c,_redis_error(error_invalid,"invalid Redis connection options") }
 if o.use_tls && len(o.tls_server_name) == 0 { return c,_redis_error(error_invalid,"TLS requires verified server name") }
 if len(o.username) != 0 && len(o.password) == 0 { return c,_redis_error(error_invalid,"ACL requires password") }
 socket,se := std.tcp.dial_ipv4(o.host,o.port,o.connect_timeout_ms)
 if se.code != 0 { return c,error {code:error_transport,native_code:se.code,message:"Redis connect failed",fatal:true} }
 c=connection {socket:socket,secure:std.tls.session {closed:true},bounds:bounds,read_timeout_ms:o.read_timeout_ms,write_timeout_ms:o.write_timeout_ms}
 if o.use_tls {
  secure,te := std.tls.connect(c.socket,o.tls_server_name,o.tls_ca_file,o.connect_timeout_ms)
  if te.code != 0 {
   failure := _redis_io_error(c*,te.code)
   return c,failure
  }
  c.secure=secure
 c.use_tls=true
 }
 if len(o.password) != 0 {
  ae := auth(c*,o.username,o.password)
  if ae.code != 0 { close(c*)
 ae.message="Redis authentication failed"
 return c,ae }
 }
 if o.database != 0 {
  de := select(c*,o.database)
  if de.code != 0 { close(c*)
 return c,de }
 }
 return c,error {}
}
