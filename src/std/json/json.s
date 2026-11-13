package std.json
import "std.prelude"
extern "intrinsic" func __host_byte_at(string value, int index) int
extern "intrinsic" func __string_slice(string value, int start, int end) string
extern "intrinsic" func __std_byte_string(int value) string
// Zero limits select 1 MiB input, 64 levels, and 4096 value nodes.
// Hard ceilings are 16 MiB, 256 levels, and 65536 nodes. Keys do not
// consume value nodes. A scalar root has depth one.
struct limits { int max_bytes, int max_depth, int max_nodes }
struct error { int code, int offset, string message }
struct node { string type_name, string value, string key, int parent }
// Documents are read-only parse results. Node indices remain stable, with
// root zero; each node records its immediate parent. Do not mutate fields.
struct document { node[] nodes, int count, string source, limits config }
struct parser { document doc, int position, error failure }
// Binary carry concatenation keeps escaped-string construction O(n log n).
struct _json_builder { string[] parts, int count, int bytes }
func _json_append(_json_builder* b, string value) {
 carry := value
 level := 0
 count := b.count
 while count % 2 == 1 {
  carry = b.parts[level] + carry
  b.parts[level] = ""
  level = level + 1
  count = count / 2
 }
 b.parts[level] = carry
 b.count = b.count + 1
 b.bytes = b.bytes + len(value)
}
func _json_built(_json_builder b) string {
 result := ""
 level := 31
 while level >= 0 {
  if len(b.parts[level]) != 0 { result = result + b.parts[level] }
  level = level - 1
 }
 return result
}
func _json_fail(parser* p, string message) {
 if p.failure.code == 0 {
  offset := p.position
  if offset > len(p.doc.source) { offset = len(p.doc.source) }
  p.failure = error {code:22,offset:offset,message:message}
 }
}
func _json_byte(parser* p) int { if p.position >= len(p.doc.source) { return -1 }
 return __host_byte_at(p.doc.source,p.position) }
func _json_space(parser* p) { while _json_byte(p) == 32 || _json_byte(p) == 9 || _json_byte(p) == 10 || _json_byte(p) == 13 { p.position = p.position + 1 } }
// Returns sequence length only for shortest-form Unicode scalar UTF-8.
func _json_utf8(string s, int i) int {
 b := __host_byte_at(s,i)
 if b < 128 { return 1 }
 n := 0
 if b >= 194 && b <= 223 { n = 2 }
 if b >= 224 && b <= 239 { n = 3 }
 if b >= 240 && b <= 244 { n = 4 }
 if n == 0 || i + n > len(s) { return 0 }
 j := 1
 while j < n { c := __host_byte_at(s,i+j)
 if c < 128 || c > 191 { return 0 }
 j = j + 1 }
 c := __host_byte_at(s,i+1)
 if (b == 224 && c < 160) || (b == 237 && c > 159) || (b == 240 && c < 144) || (b == 244 && c > 143) { return 0 }
 return n
}
func _json_hex(int b) int { if b >= 48 && b <= 57 { return b-48 }
 if b >= 65 && b <= 70 { return b-55 }
 if b >= 97 && b <= 102 { return b-87 }
 return -1 }
func _json_unit(parser* p) int {
 v := 0
 j := 0
 while j < 4 { h := _json_hex(_json_byte(p))
 if h < 0 { _json_fail(p,"invalid unicode escape")
 return 0 }
 v = v*16+h
 p.position = p.position+1
 j = j+1 }
 return v
}
func _json_encode(int v) string {
 if v < 128 { return __std_byte_string(v) }
 if v < 2048 { return __std_byte_string(192+v/64)+__std_byte_string(128+v%64) }
 if v < 65536 { return __std_byte_string(224+v/4096)+__std_byte_string(128+(v/64)%64)+__std_byte_string(128+v%64) }
 return __std_byte_string(240+v/262144)+__std_byte_string(128+(v/4096)%64)+__std_byte_string(128+(v/64)%64)+__std_byte_string(128+v%64)
}
func _json_string(parser* p) string {
 out := _json_builder {parts:make([]string,32)}
 p.position = p.position+1
 while p.position < len(p.doc.source) {
  b := _json_byte(p)
 p.position = p.position+1
  if b == 34 { return _json_built(out) }
  if b < 32 { _json_fail(p,"control in string")
 return _json_built(out) }
  if b == 92 {
   b = _json_byte(p)
 p.position = p.position+1
   if b == 34 || b == 92 || b == 47 { fragment0 := __std_byte_string(b) 
 _json_append(out*,fragment0)} else {
    if b == 98 { fragment1 := __std_byte_string(8) 
 _json_append(out*,fragment1)} else { if b == 102 { fragment2 := __std_byte_string(12) 
 _json_append(out*,fragment2)} else { if b == 110 { fragment3 := "\n" 
 _json_append(out*,fragment3)} else { if b == 114 { fragment4 := "\r" 
 _json_append(out*,fragment4)} else { if b == 116 { fragment5 := "\t" 
 _json_append(out*,fragment5)} else { if b == 117 {
     v := _json_unit(p)
     if v >= 55296 && v <= 56319 {
      if _json_byte(p) != 92 { _json_fail(p,"missing low surrogate")
 return _json_built(out) }
 p.position=p.position+1
      if _json_byte(p) != 117 { _json_fail(p,"missing low surrogate")
 return _json_built(out) }
 p.position=p.position+1
      low := _json_unit(p)
 if low < 56320 || low > 57343 { _json_fail(p,"invalid low surrogate")
 return _json_built(out) }
 v=65536+(v-55296)*1024+low-56320
     } else { if v >= 56320 && v <= 57343 { _json_fail(p,"unpaired low surrogate")
 return _json_built(out) } }
     fragment6 := _json_encode(v)
 _json_append(out*,fragment6)
    } else { _json_fail(p,"invalid escape")
 return _json_built(out) } } } } } }
   }
  } else {
   start := p.position-1
   p.position = start
   while p.position < len(p.doc.source) {
    current := _json_byte(p)
    if current < 32 || current == 34 || current == 92 { break }
    n := _json_utf8(p.doc.source,p.position)
    if n == 0 { _json_fail(p,"invalid UTF-8")
 return _json_built(out) }
    p.position = p.position+n
   }
   fragment7 := __string_slice(p.doc.source,start,p.position)
 _json_append(out*,fragment7)
  }
  if p.failure.code != 0 { return _json_built(out) }
 }
 _json_fail(p,"unterminated string")
 return _json_built(out)
}
func _json_digit(int b) bool { return b >= 48 && b <= 57 }
func _json_number(parser* p) string {
 start := p.position
 if _json_byte(p) == 45 { p.position=p.position+1 }
 if _json_byte(p) == 48 { p.position=p.position+1 } else {
  if !_json_digit(_json_byte(p)) { _json_fail(p,"expected digit")
 return "" }
  while _json_digit(_json_byte(p)) { p.position=p.position+1 }
 }
 if _json_byte(p) == 46 { p.position=p.position+1
 if !_json_digit(_json_byte(p)) { _json_fail(p,"expected fraction")
 return "" }
 while _json_digit(_json_byte(p)) { p.position=p.position+1 } }
 if _json_byte(p) == 101 || _json_byte(p) == 69 { p.position=p.position+1
 if _json_byte(p) == 43 || _json_byte(p) == 45 { p.position=p.position+1 }
 if !_json_digit(_json_byte(p)) { _json_fail(p,"expected exponent")
 return "" }
 while _json_digit(_json_byte(p)) { p.position=p.position+1 } }
 return __string_slice(p.doc.source,start,p.position)
}
func _json_value(parser* p, int parent, string key, int depth) {
 _json_space(p)
 if depth > p.doc.config.max_depth { _json_fail(p,"depth limit")
 return }
 if p.doc.count >= p.doc.config.max_nodes { _json_fail(p,"node limit")
 return }
 index := p.doc.count
 p.doc.count=p.doc.count+1
 item := node {parent:parent,key:key}
 b := _json_byte(p)
 if b == 123 || b == 91 {
  item.type_name="array"
 closing := 93
  if b == 123 { item.type_name="object"
 closing=125 }
  p.doc.nodes[index]=item
 p.position=p.position+1
 _json_space(p)
  if _json_byte(p) == closing { p.position=p.position+1
 return }
  while p.failure.code == 0 {
   member := ""
   if b == 123 {
    if _json_byte(p) != 34 { _json_fail(p,"expected object key")
 return }
    member=_json_string(p)
 _json_space(p)
    j := index+1
    while j < p.doc.count { previous := p.doc.nodes[j]
 if previous.parent == index && previous.key == member { _json_fail(p,"duplicate object key")
 return }
 j=j+1 }
    if _json_byte(p) != 58 { _json_fail(p,"expected colon")
 return }
 p.position=p.position+1
   }
   _json_value(p,index,member,depth+1)
 if p.failure.code != 0 { return }
 _json_space(p)
   if _json_byte(p) == closing { p.position=p.position+1
 return }
   if _json_byte(p) != 44 { _json_fail(p,"expected comma")
 return }
 p.position=p.position+1
 _json_space(p)
  }
  return
 }
 if b == 34 { item.type_name="string"
 item.value=_json_string(p) } else {
  if b == 45 || _json_digit(b) { item.type_name="number"
 item.value=_json_number(p) } else {
   literal := ""
 item.type_name="bool"
   if b == 116 { literal="true" }
 if b == 102 { literal="false" }
 if b == 110 { literal="null"
 item.type_name="null" }
   if literal == "" { _json_fail(p,"expected value")
 return }
   j := 0
   while j < len(literal) { if _json_byte(p) != __host_byte_at(literal,j) { _json_fail(p,"invalid literal")
 return }
 p.position=p.position+1
 j=j+1 }
   item.value=literal
  }
 }
 p.doc.nodes[index]=item
}
func parse(string source, limits requested) (document,error) {
 config := requested
 if config.max_bytes == 0 { config.max_bytes=1048576 }
 if config.max_depth == 0 { config.max_depth=64 }
 if config.max_nodes == 0 { config.max_nodes=4096 }
 if config.max_bytes < 1 || config.max_bytes > 16777216 || config.max_depth < 1 || config.max_depth > 256 || config.max_nodes < 1 || config.max_nodes > 65536 { return document {},error {code:22,message:"invalid limits"} }
 if len(source) > config.max_bytes { return document {},error {code:22,message:"byte limit"} }
 p := parser {doc:document {source:source,config:config,nodes:make([]node,config.max_nodes)}}
 _json_value(p*,-1,"",1)
 _json_space(p*)
 if p.failure.code == 0 && p.position != len(source) { _json_fail(p*,"trailing input") }
 if p.failure.code != 0 { return document {},p.failure }
 return p.doc,error {}
}
func kind(document d, int index) string { if index < 0 || index >= d.count { return "" }
 return d.nodes[index].type_name }
func text(document d, int index) string { if index < 0 || index >= d.count { return "" }
 return d.nodes[index].value }
func get(document d, int object_index, string key) int {
 if kind(d,object_index) != "object" { return -1 }
 i:=object_index+1
 while i < d.count { n:=d.nodes[i]
 if n.parent == object_index && n.key == key { return i }
 i=i+1 }
 return -1
}
func at(document d, int array_index, int ordinal) int {
 if kind(d,array_index) != "array" || ordinal < 0 { return -1 }
 i:=array_index+1
 seen:=0
 while i < d.count { if d.nodes[i].parent == array_index { if seen == ordinal { return i }
 seen=seen+1 }
 i=i+1 }
 return -1
}
// quote validates Unicode and bounds both input and escaped output to 1 MiB.
func quote(string value) (string,error) {
 if len(value) > 1048576 { return "",error {code:22,message:"quote byte limit"} }
 out := _json_builder {parts:make([]string,32)}
 fragment8 := "\""
 _json_append(out*,fragment8)
 i := 0
 digits := "0123456789abcdef"
 while i < len(value) {
  b := __host_byte_at(value,i)
  if b == 34 || b == 92 {
   fragment9 := "\\"+__std_byte_string(b)
 _json_append(out*,fragment9)
   i=i+1
  } else {
   if b < 32 {
    fragment10 := "\\u00"+__string_slice(digits,b/16,b/16+1)+__string_slice(digits,b%16,b%16+1)
 _json_append(out*,fragment10)
    i=i+1
   } else {
    start := i
    while i < len(value) {
     current := __host_byte_at(value,i)
     if current < 32 || current == 34 || current == 92 { break }
     n := _json_utf8(value,i)
     if n == 0 { return "",error {code:22,offset:i,message:"invalid UTF-8"} }
     i=i+n
    }
    fragment11 := __string_slice(value,start,i)
 _json_append(out*,fragment11)
   }
  }
  if out.bytes+1 > 1048576 { return "",error {code:22,offset:i,message:"quote byte limit"} }
 }
 fragment12 := "\""
 _json_append(out*,fragment12)
 return _json_built(out),error {}
}
// Parsed documents preserve their validated JSON spelling and number precision.
func serialize(document d) (string,error) {
 checked,e:=parse(d.source,d.config)
 if e.code != 0 { return "",e }
 return checked.source,error {}
}
