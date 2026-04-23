package demo.member

struct point {
    int32 x
    int32 y
}

trait measure {
    func size(point self) int32;
}

impl measure for point {
    func size(point self) int32 {
        self.x + self.y
    }
}

func total(point p, vec[int32] items, int32 index) int32 {
    p.size() + items[index]
}
