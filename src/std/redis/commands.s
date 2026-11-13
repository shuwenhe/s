package std.redis
func _redis_typed(connection* c) error {
 if c.closed { return _redis_error(error_closed,"Redis connection closed") }
 if c.in_multi { return _redis_error(error_state,"use execute to queue transaction commands") }
 return error {}
}
func _redis_unexpected(connection* c) error {
 return _redis_fatal(c*,error_protocol,0,"unexpected Redis reply type")
}
func _redis_status(connection* c, string[] args, string expected) error {
 guard := _redis_typed(c*)
 if guard.code != 0 { return guard }
 reply,e := execute(c*,args)
 if e.code != 0 { return e }
 if reply.nodes[0].kind != "simple" || reply.nodes[0].text != expected { return _redis_unexpected(c*) }
 return error {}
}
func _redis_integer(connection* c, string[] args) (int,error) {
 guard := _redis_typed(c*)
 if guard.code != 0 { return 0,guard }
 reply,e := execute(c*,args)
 if e.code != 0 { return 0,e }
 if reply.nodes[0].kind != "integer" { return 0,_redis_unexpected(c*) }
 return reply.nodes[0].integer,error {}
}
func _redis_optional(connection* c, string[] args) (optional_string,error) {
 guard := _redis_typed(c*)
 if guard.code != 0 { return optional_string {},guard }
 reply,e := execute(c*,args)
 if e.code != 0 { return optional_string {},e }
 if reply.nodes[0].kind == "null_bulk" { return optional_string {},error {} }
 if reply.nodes[0].kind != "bulk" { return optional_string {},_redis_unexpected(c*) }
 return optional_string {present:true,value:reply.nodes[0].text},error {}
}
func _redis_array(connection* c, string[] args, bool pairs) (document,error) {
 guard := _redis_typed(c*)
 if guard.code != 0 { return document {},guard }
 reply,e := execute(c*,args)
 if e.code != 0 { return reply,e }
 if reply.nodes[0].kind != "array" { return reply,_redis_unexpected(c*) }
 if pairs && reply.nodes[0].length%2 != 0 { return reply,_redis_unexpected(c*) }
 i := 1
 while i < reply.count {
  if reply.nodes[i].kind != "bulk" || reply.nodes[i].parent != 0 { return reply,_redis_unexpected(c*) }
  i=i+1
 }
 return reply,error {}
}
func ping(connection* c) error {
 arguments := []string {"PING"}
 return _redis_status(c*,arguments,"PONG")
}
func auth(connection* c, string username, string password) error {
 password_arguments := []string {"AUTH",password}
 if username == "" { return _redis_status(c*,password_arguments,"OK") }
 arguments := []string {"AUTH",username,password}
 return _redis_status(c*,arguments,"OK")
}
func select(connection* c, int database) error {
 if database < 0 { return _redis_error(error_invalid,"negative Redis database") }
 arguments := []string {"SELECT",std.prelude.to_string(database)}
 return _redis_status(c*,arguments,"OK")
}
func get(connection* c, string key) (optional_string,error) {
 arguments := []string {"GET",key}
 return _redis_optional(c*,arguments)
}
func set(connection* c, string key, string value, set_options o) (bool,error) {
 guard := _redis_typed(c*)
 if guard.code != 0 { return false,guard }
 if o.ex_seconds < 0 || o.px_milliseconds < 0 || (o.ex_seconds != 0 && o.px_milliseconds != 0) || (o.nx && o.xx) { return false,_redis_error(error_invalid,"conflicting SET options") }
 count := 3
 if o.ex_seconds != 0 || o.px_milliseconds != 0 { count=count+2 }
 if o.nx || o.xx { count=count+1 }
 args := make([]string,count)
 args[0]="SET"
 args[1]=key
 args[2]=value
 index := 3
 if o.ex_seconds != 0 { args[index]="EX"
 args[index+1]=std.prelude.to_string(o.ex_seconds)
 index=index+2 }
 if o.px_milliseconds != 0 { args[index]="PX"
 args[index+1]=std.prelude.to_string(o.px_milliseconds)
 index=index+2 }
 if o.nx { args[index]="NX" }
 if o.xx { args[index]="XX" }
 reply,e := execute(c*,args)
 if e.code != 0 { return false,e }
 if reply.nodes[0].kind == "null_bulk" && (o.nx || o.xx) { return false,error {} }
 if reply.nodes[0].kind != "simple" || reply.nodes[0].text != "OK" { return false,_redis_unexpected(c*) }
 return true,error {}
}
func type(connection* c, string key) (string,error) {
 guard := _redis_typed(c*)
 if guard.code != 0 { return "",guard }
 arguments := []string {"TYPE",key}
 reply,e := execute(c*,arguments)
 if e.code != 0 { return "",e }
 if reply.nodes[0].kind != "simple" { return "",_redis_unexpected(c*) }
 return reply.nodes[0].text,error {}
}
func _redis_boolean(connection* c, string[] args) (bool,error) {
 n,e := _redis_integer(c*,args)
 if e.code != 0 { return false,e }
 if n != 0 && n != 1 { return false,_redis_unexpected(c*) }
 return n == 1,error {}
}
func del(connection* c, string key) (int,error) {
 arguments := []string {"DEL",key}
 return _redis_integer(c*,arguments)
}
func exists(connection* c, string key) (int,error) {
 arguments := []string {"EXISTS",key}
 return _redis_integer(c*,arguments)
}
func ttl(connection* c, string key) (int,error) {
 arguments := []string {"TTL",key}
 return _redis_integer(c*,arguments)
}
func expire(connection* c, string key, int seconds) (bool,error) {
 arguments := []string {"EXPIRE",key,std.prelude.to_string(seconds)}
 return _redis_boolean(c*,arguments)
}
func persist(connection* c, string key) (bool,error) {
 arguments := []string {"PERSIST",key}
 return _redis_boolean(c*,arguments)
}
func hset(connection* c, string key, string field, string value) (int,error) {
 arguments := []string {"HSET",key,field,value}
 return _redis_integer(c*,arguments)
}
func hget(connection* c, string key, string field) (optional_string,error) {
 arguments := []string {"HGET",key,field}
 return _redis_optional(c*,arguments)
}
func hgetall(connection* c, string key) (document,error) {
 arguments := []string {"HGETALL",key}
 return _redis_array(c*,arguments,true)
}
func hdel(connection* c, string key, string field) (int,error) {
 arguments := []string {"HDEL",key,field}
 return _redis_integer(c*,arguments)
}
func hexists(connection* c, string key, string field) (bool,error) {
 arguments := []string {"HEXISTS",key,field}
 return _redis_boolean(c*,arguments)
}
func lpush(connection* c, string key, string value) (int,error) {
 arguments := []string {"LPUSH",key,value}
 return _redis_integer(c*,arguments)
}
func rpush(connection* c, string key, string value) (int,error) {
 arguments := []string {"RPUSH",key,value}
 return _redis_integer(c*,arguments)
}
func lpop(connection* c, string key) (optional_string,error) {
 arguments := []string {"LPOP",key}
 return _redis_optional(c*,arguments)
}
func rpop(connection* c, string key) (optional_string,error) {
 arguments := []string {"RPOP",key}
 return _redis_optional(c*,arguments)
}
func lrange(connection* c, string key, int start, int end) (document,error) {
 arguments := []string {"LRANGE",key,std.prelude.to_string(start),std.prelude.to_string(end)}
 return _redis_array(c*,arguments,false)
}
func sadd(connection* c, string key, string value) (int,error) {
 arguments := []string {"SADD",key,value}
 return _redis_integer(c*,arguments)
}
func srem(connection* c, string key, string value) (int,error) {
 arguments := []string {"SREM",key,value}
 return _redis_integer(c*,arguments)
}
func smembers(connection* c, string key) (document,error) {
 arguments := []string {"SMEMBERS",key}
 return _redis_array(c*,arguments,false)
}
func sismember(connection* c, string key, string value) (bool,error) {
 arguments := []string {"SISMEMBER",key,value}
 return _redis_boolean(c*,arguments)
}
