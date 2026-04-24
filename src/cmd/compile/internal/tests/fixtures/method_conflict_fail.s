package demo.conflict

struct point {
    int x
}

trait measure_a {
    func size(point self) int;
}

trait measure_b {
    func size(point self) int;
}

impl measure_a for point {
    func size(point self) int {
        self.x
    }
}

impl measure_b for point {
    func size(point self) int {
        self.x
    }
}

func bad(point p) int {
    p.size()
}
