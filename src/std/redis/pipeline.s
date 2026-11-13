package std.redis
func pipeline(connection* c, command[] commands) (batch,error) {
 if c.closed { return batch {},_redis_error(error_closed,"Redis connection closed") }
 if c.busy || c.in_multi || c.watched { return batch {},_redis_error(error_state,"pipeline requires idle unwatched connection") }
 if len(commands) == 0 || len(commands) > 128 { return batch {},_redis_error(error_bounds,"pipeline count must be 1..128") }
 // Validate and encode the entire batch before sending anything.
 parts := make([]string,len(commands))
 size := 0
 i := 0
 while i < len(commands) {
  args := commands[i].arguments
  ve := _redis_validate(args)
  if ve.code != 0 { return batch {},ve }
  v := _redis_verb(args[0])
  if v == "MULTI" || v == "EXEC" || v == "DISCARD" || v == "WATCH" || v == "UNWATCH" || v == "AUTH" || v == "SELECT" { return batch {},_redis_error(error_state,"pipeline cannot change connection state") }
  wire,e := encode(args,c.bounds)
  if e.code != 0 { return batch {},e }
  if len(wire) > c.bounds.max_frame_bytes-size { return batch {},_redis_error(error_bounds,"pipeline byte limit") }
  parts[i]=wire
  size=size+len(wire)
  i=i+1
 }
 wire := _redis_join(parts,0,len(parts))
 c.busy=true
 we := _redis_write(c*,wire)
 if we.code != 0 { c.busy=false
 return batch {},we }
 deadline,de := _redis_deadline(c.read_timeout_ms)
 if de.code != 0 { c.busy=false
 return batch {},_redis_fatal(c*,de.code,de.native_code,de.message) }
 out := batch {replies:make([]document,len(commands))}
 total := 0
 total_bytes := 0
 i=0
 while i < len(commands) {
  reply,e := _redis_read(c*,deadline)
  if e.code != 0 { c.busy=false
 return out,e }
  if c.last_reply_bytes > c.bounds.max_frame_bytes-total_bytes { c.busy=false
 return out,_redis_fatal(c*,error_bounds,0,"pipeline response byte limit") }
  total_bytes=total_bytes+c.last_reply_bytes
  if reply.count > c.bounds.max_nodes-total { c.busy=false
 return out,_redis_fatal(c*,error_bounds,0,"pipeline node limit") }
  total=total+reply.count
  out.replies[i]=reply
  out.count=i+1
  i=i+1
 }
 c.busy=false
 if len(c.buffered) != 0 { return out,_redis_fatal(c*,error_protocol,0,"unsolicited pipeline bytes") }
 return out,error {}
}
func _redis_join(string[] parts, int start, int end) string {
 if start == end { return "" }
 if end-start == 1 { return parts[start] }
 middle := start+(end-start)/2
 return _redis_join(parts,start,middle)+_redis_join(parts,middle,end)
}
