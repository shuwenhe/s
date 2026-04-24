package demo.member

struct point {
    int x
    int y
}

trait measure {
    func size(point self) int;
}

impl measure for point {
    func size(point self) int {
        self.x + self.y
    }
}

func total(point p, vec[int] items, int index) int {
    p.size() + items[index]
}
