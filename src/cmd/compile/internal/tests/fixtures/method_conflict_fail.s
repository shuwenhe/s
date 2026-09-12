package demo.conflict
struct point {
    x int
}
trait measure_a {
    func size() int;
}
trait measure_b {
    func size() int;
}

func ( p point) size() int {
    p.x
}

func ( p point) size() int {
    p.x
}

func bad(point p) int {
    p.size()
}