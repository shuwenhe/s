// Data-only REST routing. Patterns have literal or :name segments, no trailing
// slash except /. First differing segment prefers literals. Method selection
// happens after path precedence. HEAD falls back to GET. Query duplicates retain
// order; query_value returns the first. Path and query inputs are separate.
package std.rest
struct param { string name, string value }
struct route { string method, string pattern, int handler_id, param[] segments }
struct router { route[] routes }
func new() router { return router {routes:[]route{}} }
struct error { int code, string message }
struct match_result { int status, int handler_id, string allow, param[] parameters }
extern "intrinsic" func __host_byte_at(string text,int index) int
extern "intrinsic" func __string_slice(string text,int start,int end) string
extern "intrinsic" func __std_byte_string(int byte) string
func _rest_bad(string message) error { return error {code:22,message:message} }
func _rest_hex(int b) int {
    if b >= 48 && b <= 57 { return b - 48 }
    if b >= 65 && b <= 70 { return b - 55 }
    if b >= 97 && b <= 102 { return b - 87 }
    return -1
}
func _rest_utf8(string s) bool {
    i := 0
    while i < len(s) {
        b := __host_byte_at(s,i)
        n := 0
        low := 128
        high := 191
        if b >= 128 {
            if b >= 194 && b <= 223 { n = 1 } else {
                if b >= 224 && b <= 239 { n = 2; if b == 224 { low = 160 } if b == 237 { high = 159 } } else {
                    if b >= 240 && b <= 244 { n = 3; if b == 240 { low = 144 } if b == 244 { high = 143 } } else { return false }
                }
            }
            if i + n >= len(s) { return false }
            j := 1
            while j <= n {
                c := __host_byte_at(s,i+j)
                if c < low || c > high { return false }
                low = 128; high = 191; j = j + 1
            }
        }
        i = i + n + 1
    }
    return true
}
func _rest_decode(string raw,bool query) (string,error) {
    out := ""
    i := 0
    while i < len(raw) {
        b := __host_byte_at(raw,i)
        if b == 37 {
            if i + 2 >= len(raw) { return "",_rest_bad("incomplete percent escape") }
            a := _rest_hex(__host_byte_at(raw,i+1)); c := _rest_hex(__host_byte_at(raw,i+2))
            if a < 0 || c < 0 { return "",_rest_bad("invalid percent escape") }
            b = a*16+c; i = i+2
        } else { if query && b == 43 { b = 32 } }
        if b < 32 || b == 127 || (!query && (b == 47 || b == 92)) { return "",_rest_bad("forbidden decoded byte") }
        out = out + __std_byte_string(b); i = i+1
    }
    if !_rest_utf8(out) { return "",_rest_bad("invalid UTF-8") }
    return out,error {code:0}
}
func _rest_segments(string path,bool pattern) (param[],error) {
    parts := []param{}
    if len(path) == 0 || len(path) > 8192 || __host_byte_at(path,0) != 47 { return parts,_rest_bad("invalid absolute path") }
    if path == "/" { return parts,error {code:0} }
    start := 1; i := 1
    while i <= len(path) {
        if i == len(path) || __host_byte_at(path,i) == 47 {
            if i == start { return parts,_rest_bad("empty path segment") }
            raw := __string_slice(path,start,i)
            if pattern && __host_byte_at(raw,0) == 58 {
                name := __string_slice(raw,1,len(raw))
                if len(name) == 0 { return parts,_rest_bad("empty parameter name") }
                j := 0
                while j < len(name) {
                    b := __host_byte_at(name,j)
                    if !((b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b == 95 || (j > 0 && b >= 48 && b <= 57)) { return parts,_rest_bad("invalid parameter name") }
                    j = j+1
                }
                j = 0
                while j < len(parts) { previous := parts[j]; if previous.name == name { return parts,_rest_bad("duplicate parameter name") } j = j+1 }
                parts = append(parts,param {name:name})
            } else {
                text,err := _rest_decode(raw,false)
                if err.code != 0 { return parts,err }
                if text == "." || text == ".." { return parts,_rest_bad("dot path segment") }
                j := 0
                while j < len(text) { b := __host_byte_at(text,j); if b == 63 || b == 35 || (pattern && b == 58) { return parts,_rest_bad("invalid path delimiter") } j=j+1 }
                parts = append(parts,param {value:text})
            }
            start = i+1
        }
        i=i+1
    }
    return parts,error {code:0}
}
func _rest_method(string method) bool { return method == "GET" || method == "HEAD" || method == "POST" || method == "PUT" || method == "DELETE" }
func add(router target,string method,string pattern,int handler_id) (router,error) {
    if !_rest_method(method) { return target,_rest_bad("unsupported method") }
    parts,err := _rest_segments(pattern,true)
    if err.code != 0 { return target,err }
    i := 0
    while i < len(target.routes) {
        old := target.routes[i]
        if old.method == method && len(old.segments) == len(parts) {
            same := true; j := 0
            while j < len(parts) {
                a := old.segments[j]; b := parts[j]
                if (a.name == "") != (b.name == "") || (a.name == "" && a.value != b.value) { same = false }
                j=j+1
            }
            if same { return target,_rest_bad("duplicate route shape") }
        }
        i=i+1
    }
    existing := target.routes
    next := append(existing,route {method:method,pattern:pattern,handler_id:handler_id,segments:parts})
    target.routes = next
    return target,error {code:0}
}
func _rest_fits(param[] pattern,param[] path) bool {
    if len(pattern) != len(path) { return false }
    i:=0
    while i<len(path) { segment := pattern[i]; actual := path[i]; if segment.name == "" && segment.value != actual.value { return false } i=i+1 }
    return true
}
func _rest_priority(param[] a,param[] b) int {
    i:=0
    while i<len(a) {
        left := a[i]; right := b[i]
        if left.name == "" && right.name != "" { return 1 }
        if left.name != "" && right.name == "" { return -1 }
        i=i+1
    }
    return 0
}
func match(router source,string method,string path) (match_result,error) {
    parts,err := _rest_segments(path,false)
    if err.code != 0 { return match_result {status:400},err }
    best := -1; i:=0
    while i<len(source.routes) {
        candidate := source.routes[i]
        if _rest_fits(candidate.segments,parts) {
            if best < 0 { best=i } else { previous := source.routes[best]; if _rest_priority(candidate.segments,previous.segments)>0 { best=i } }
        }
        i=i+1
    }
    if best < 0 { return match_result {status:404},error {code:0} }
    preferred := source.routes[best]
    selected := -1; fallback := -1
    get:=false; head:=false; post:=false; put:=false; delete:=false
    i=0
    while i<len(source.routes) {
        candidate:=source.routes[i]
        if _rest_fits(candidate.segments,parts) && _rest_priority(candidate.segments,preferred.segments)==0 {
            if candidate.method==method { selected=i }
            if candidate.method=="GET" { get=true; fallback=i }
            if candidate.method=="HEAD" { head=true }
            if candidate.method=="POST" { post=true }
            if candidate.method=="PUT" { put=true }
            if candidate.method=="DELETE" { delete=true }
        }
        i=i+1
    }
    allow:=""
    if get { allow="GET" }
    if head || get { if allow!="" { allow=allow+", " } allow=allow+"HEAD" }
    if post { if allow!="" { allow=allow+", " } allow=allow+"POST" }
    if put { if allow!="" { allow=allow+", " } allow=allow+"PUT" }
    if delete { if allow!="" { allow=allow+", " } allow=allow+"DELETE" }
    if selected<0 && method=="HEAD" { selected=fallback }
    if selected<0 { return match_result {status:405,allow:allow},error {code:0} }
    parameters:=[]param{} i=0
    chosen:=source.routes[selected]
    while i<len(parts) { segment := chosen.segments[i]; actual := parts[i]; if segment.name!="" { parameters=append(parameters,param {name:segment.name,value:actual.value}) } i=i+1 }
    return match_result {status:200,handler_id:chosen.handler_id,parameters:parameters},error {code:0}
}
func query_value(param[] values,string name) string {
    i:=0
    while i<len(values) { item := values[i]; if item.name==name { return item.value } i=i+1 }
    return ""
}
func param_value(match_result result,string name) string { return query_value(result.parameters,name) }
func parse_query(string raw) (param[],error) {
    values:=[]param{}
    if len(raw)>8192 { return values,_rest_bad("query exceeds 8192 bytes") }
    if len(raw)==0 { return values,error {code:0} }
    start:=0; i:=0
    while i<=len(raw) {
        if i==len(raw) || __host_byte_at(raw,i)==38 {
            if len(values)>=64 { return []param{},_rest_bad("query exceeds 64 pairs") }
            equal:=start
            while equal<i && __host_byte_at(raw,equal)!=61 { equal=equal+1 }
            name,ne:=_rest_decode(__string_slice(raw,start,equal),true)
            value:=""; ve:=error {code:0}
            if equal<i { decoded,de := _rest_decode(__string_slice(raw,equal+1,i),true); value=decoded; ve=de }
            if ne.code!=0 { return []param{},ne } if ve.code!=0 { return []param{},ve }
            values=append(values,param {name:name,value:value}); start=i+1
        }
        i=i+1
    }
    return values,error {code:0}
}
