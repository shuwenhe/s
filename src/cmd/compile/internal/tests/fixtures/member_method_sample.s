package demo.member

struct Point {
    int32 x,
    int32 y,
}

trait Measure {
    func size(Point self) int32;
}

impl Measure for Point {
    func size(Point self) int32 {
        self.x + self.y
    }
}

func total(Point p, Vec[int32] items, int32 index) int32 {
    p.size() + items[index]
}
