package demo.conflict

struct Point {
    int32 x,
}

trait measure_a {
    func size(Point self) int32;
}

trait measure_b {
    func size(Point self) int32;
}

impl measure_a for Point {
    func size(Point self) int32 {
        self.x
    }
}

impl measure_b for Point {
    func size(Point self) int32 {
        self.x
    }
}

func bad(Point p) int32 {
    p.size()
}
