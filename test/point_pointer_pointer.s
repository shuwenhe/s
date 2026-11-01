package test.compiler

struct Point { x: int }

func consume_point_pp(p **Point) int { return (*p).x }
func consume_point_p(p *Point) int { return p.x }

func main() int {
    
    p := Point { x: 42 }
    pp := &p
    ppp := &pp
    result1 := consume_point_pp(ppp)
    return result1
}
