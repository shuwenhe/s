package std.redis
func multi(connection* c) error {
 if c.in_multi { return _redis_error(error_state,"MULTI already active") }
 bound_args_1 := []string {"MULTI"}
 return _redis_status(c*,bound_args_1,"OK")
}
func exec(connection* c) (document,error) {
 if !c.in_multi { return document {},_redis_error(error_state,"EXEC requires MULTI") }
 bound_args_2 := []string {"EXEC"}
 reply,e := execute(c*,bound_args_2)
 if e.code != 0 { return reply,e }
 if reply.nodes[0].kind != "array" && reply.nodes[0].kind != "null_array" { return reply,_redis_unexpected(c*) }
 return reply,error {}
}
func discard(connection* c) error {
 if !c.in_multi { return _redis_error(error_state,"DISCARD requires MULTI") }
 bound_args_3 := []string {"DISCARD"}
 reply,e := execute(c*,bound_args_3)
 if e.code != 0 { return e }
 if reply.nodes[0].kind != "simple" || reply.nodes[0].text != "OK" { return _redis_unexpected(c*) }
 return error {}
}
func watch(connection* c, string key) error {
 bound_args_4 := []string {"WATCH",key}
 return _redis_status(c*,bound_args_4,"OK")
}
func unwatch(connection* c) error {
 bound_args_5 := []string {"UNWATCH"}
 return _redis_status(c*,bound_args_5,"OK")
}
