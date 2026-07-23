package demo.member

struct point {
    int x
    int y
}

trait measure {
    func size() int;
}

func (p: point) size() int {
    p.x + p.y
}

func total(point p, vec[int] items, int index) int {
    p.size() + items[index]
}
