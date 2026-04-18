package demo.conflict

struct point {
    int32 x,
}

trait measure_a {
    func size(point self) int32;
}

trait measure_b {
    func size(point self) int32;
}

impl measure_a for point {
    func size(point self) int32 {
        self.x
    }
}

impl measure_b for point {
    func size(point self) int32 {
        self.x
    }
}

func bad(point p) int32 {
    p.size()
}
