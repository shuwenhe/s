package main
import "std.json"
extern "intrinsic" func __std_byte_string(int value) string
func rejected(string s) bool { d,e := std.json.parse(s,std.json.limits {}); return e.code != 0 }
func more_cases() int {
 if !rejected("") || !rejected(" ") || !rejected("[") || !rejected("{") || !rejected("[1 2]") || !rejected("{\"a\" 1}") || !rejected("{\"a\":1,}") { return 10 }
 if !rejected("-.1") || !rejected("00") || !rejected("-01") || !rejected("NaN") || !rejected("Infinity") || !rejected("1e") || !rejected("1E-") || !rejected("falsex") || !rejected("nul") { return 11 }
 if !rejected("\"" + __std_byte_string(10) + "\"") || !rejected("\"\\u12xz\"") || !rejected("\"\\uD800\\u0000\"") { return 12 }
 if !rejected("\"" + __std_byte_string(237) + __std_byte_string(160) + __std_byte_string(128) + "\"") { return 13 }
 if !rejected("\"" + __std_byte_string(244) + __std_byte_string(144) + __std_byte_string(128) + __std_byte_string(128) + "\"") { return 14 }
 if !rejected("\"" + __std_byte_string(226) + __std_byte_string(130) + "\"") { return 15 }
 good,ge := std.json.parse(" \t\r\n[0,-0,10,0.1,1E-9,false,null,{},[],\"\\b\\f\\r\\t\\/\\u0000\\uFFFF\"] ",std.json.limits {})
 if ge.code != 0 || std.json.kind(good,std.json.at(good,0,5)) != "bool" || std.json.text(good,std.json.at(good,0,6)) != "null" { return 16 }
 exact,ee := std.json.parse("[[0]]",std.json.limits {max_bytes:5,max_depth:3,max_nodes:3})
 if ee.code != 0 || std.json.kind(exact,std.json.at(exact,std.json.at(exact,0,0),0)) != "number" { return 17 }
 invalid,ie := std.json.parse("0",std.json.limits {max_depth:-1})
 if ie.code == 0 { return 18 }
 q,qe := std.json.quote("😀\\")
 if qe.code != 0 { return 19 }
 return 0
}
func large_string() int {
 long := "x"
 i := 0
 while i < 18 { long=long+long; i=i+1 }
 q,e := std.json.quote(long)
 if e.code != 0 { return 20 }
 d,de := std.json.parse(q,std.json.limits {})
 if de.code != 0 || std.json.text(d,0) != long { return 21 }
 escaped := "\n"
 j := 0
 while j < 15 { escaped=escaped+escaped; j=j+1 }
 eq,ee := std.json.quote(escaped)
 ed,ede := std.json.parse(eq,std.json.limits {})
 if ee.code != 0 || ede.code != 0 || std.json.text(ed,0) != escaped { return 22 }

 return 0
}
func main() int {
 if large_string() != 0 { return large_string() }

 if more_cases() != 0 { return more_cases() }

 d,e := std.json.parse("{\"a\":[\"\\uD83D\\uDE00\",-1.25e+2,true,null],\"b\":\"x\\n\"}",std.json.limits {})
 if e.code != 0 || std.json.kind(d,0) != "object" { return 1 }
 a := std.json.get(d,0,"a")
 if std.json.text(d,std.json.at(d,a,0)) != "😀" || std.json.text(d,std.json.at(d,a,1)) != "-1.25e+2" { return 2 }
 if std.json.get(d,0,"missing") != -1 || std.json.at(d,a,4) != -1 { return 3 }
 wire,se := std.json.serialize(d)
 again,ae := std.json.parse(wire,std.json.limits {})
 if se.code != 0 || ae.code != 0 || std.json.text(again,std.json.get(again,0,"b")) != "x\n" { return 4 }
 if !rejected("{\"x\":1,\"\\u0078\":2}") || !rejected("[1,]") || !rejected("{\"a\":}") || !rejected("01") || !rejected("1.") || !rejected("1e+") || !rejected("+1") || !rejected("true false") { return 5 }
 if !rejected("\"\\uD800\"") || !rejected("\"\\uDC00\"") || !rejected("\"\\x20\"") || !rejected("\"" + __std_byte_string(192) + __std_byte_string(128) + "\"") { return 6 }
 x,xe := std.json.parse("[[0]]",std.json.limits {max_depth:2})
 y,ye := std.json.parse("[0,1]",std.json.limits {max_nodes:2})
 z,ze := std.json.parse("null",std.json.limits {max_bytes:3})
 if xe.code == 0 || ye.code == 0 || ze.code == 0 { return 7 }
 q,qe := std.json.quote("\n\t\"\\" + __std_byte_string(0) + "中文")
 qd,qde := std.json.parse(q,std.json.limits {})
 if qe.code != 0 || qde.code != 0 || std.json.text(qd,0) != "\n\t\"\\" + __std_byte_string(0) + "中文" { return 8 }
 bad,be := std.json.quote(__std_byte_string(255))
 if be.code == 0 { return 9 }
 println("json: PASS")
 return 0
}
