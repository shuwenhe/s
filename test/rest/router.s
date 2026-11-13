package main
import "std.rest"
func main() int {
    r := std.rest.new()
    e := std.rest.error {code:0}
    next1, e1 := std.rest.add(r,"GET","/users/:id",1)
    r = next1
    e = e1
    if e.code != 0 { return 1 }
    next2, e2 := std.rest.add(r,"GET","/users/new",2)
    r = next2
    e = e2
    if e.code != 0 { return 2 }
    found, err := std.rest.match(r,"GET","/users/new")
    if err.code != 0 || found.status != 200 || found.handler_id != 2 { return 3 }
    found3, err3 := std.rest.match(r,"GET","/users/a%20b")
    found = found3
    err = err3
    if err.code != 0 || std.rest.param_value(found,"id") != "a b" { return 4 }
    found4, err4 := std.rest.match(r,"POST","/users/new")
    found = found4
    err = err4
    if found.status != 405 || found.allow != "GET, HEAD" { return 5 }
    found5, err5 := std.rest.match(r,"HEAD","/users/new")
    found = found5
    err = err5
    if found.handler_id != 2 || found.status != 200 { return 6 }
    found6, err6 := std.rest.match(r,"GET","/missing")
    found = found6
    err = err6
    if found.status != 404 { return 7 }
    next7, e7 := std.rest.add(r,"GET","/users/:name",3)
    r = next7
    e = e7
    if e.code == 0 { return 8 }
    next8, e8 := std.rest.add(r,"GET","/:id/:id",3)
    r = next8
    e = e8
    if e.code == 0 { return 9 }
    found9, err9 := std.rest.match(r,"GET","/users/%2f")
    found = found9
    err = err9
    if err.code == 0 || found.status != 400 { return 10 }
    found10, err10 := std.rest.match(r,"GET","/users/%ff")
    found = found10
    err = err10
    if err.code == 0 { return 11 }
    q, qe := std.rest.parse_query("name=a+b&name=c%26d&empty=")
    if qe.code != 0 || len(q) != 3 || q[1].value != "c&d" || std.rest.query_value(q,"name") != "a b" { return 12 }
    q11, qe11 := std.rest.parse_query("x=%0z")
    q = q11
    qe = qe11
    if qe.code == 0 { return 13 }
    q12, qe12 := std.rest.parse_query("x=%00")
    q = q12
    qe = qe12
    if qe.code == 0 { return 14 }
    next13, e13 := std.rest.add(r,"POST","/users/new",4)
    r = next13
    e = e13
    found14, err14 := std.rest.match(r,"DELETE","/users/new")
    found = found14
    err = err14
    if found.allow != "GET, HEAD, POST" { return 15 }
    next15, e15 := std.rest.add(r,"HEAD","/users/new",5)
    r = next15
    e = e15
    found16, err16 := std.rest.match(r,"HEAD","/users/new")
    found = found16
    err = err16
    if found.handler_id != 5 { return 16 }
    // Reverse registration must produce identical static-path selection.
    reverse := std.rest.new()
    rev1, re1 := std.rest.add(reverse,"GET","/users/new",2)
    rev2, re2 := std.rest.add(rev1,"GET","/users/:id",1)
    revmatch, rev_error := std.rest.match(rev2,"GET","/users/new")
    if re1.code != 0 || re2.code != 0 || rev_error.code != 0 || revmatch.handler_id != 2 { return 17 }
    invalid1, ie1 := std.rest.add(r,"GET","/bad/",20)
    invalid2, ie2 := std.rest.add(r,"PATCH","/ok",20)
    invalid3, ie3 := std.rest.add(r,"GET","/bad/:",20)
    invalid4, ie4 := std.rest.add(r,"GET","/bad/%2f",20)
    if ie1.code == 0 || ie2.code == 0 || ie3.code == 0 || ie4.code == 0 { return 18 }
    badslash, bs := std.rest.match(r,"GET","/users/%5c")
    badnull, bn := std.rest.match(r,"GET","/users/%00")
    badutf, bu := std.rest.match(r,"GET","/users/%c0%af")
    badquery, bq := std.rest.match(r,"GET","/users/new?q=1")
    if bs.code == 0 || bn.code == 0 || bu.code == 0 || bq.code == 0 { return 19 }
    unicode, ue := std.rest.match(r,"GET","/users/%E4%B8%AD")
    if ue.code != 0 || std.rest.param_value(unicode,"id") != "中" { return 20 }
    raw := ""
    count := 0
    while count < 64 { if count > 0 { raw = raw + "&" } raw = raw + "x=1"; count = count + 1 }
    bounded, be := std.rest.parse_query(raw)
    if be.code != 0 || len(bounded) != 64 { return 21 }
    excessive, ee := std.rest.parse_query(raw + "&x=2")
    if ee.code == 0 || len(excessive) != 0 { return 22 }
    long := ""
    count = 0
    while count < 8193 { long = long + "a"; count = count + 1 }
    oversized, oe := std.rest.parse_query(long)
    if oe.code == 0 { return 23 }
    root1, rooterr := std.rest.add(r,"PUT","/",33)
    rootmatch, rmerr := std.rest.match(root1,"PUT","/")
    if rooterr.code != 0 || rmerr.code != 0 || rootmatch.handler_id != 33 { return 24 }
    println("rest router: PASS")
    return 0
}
