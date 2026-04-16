package demo.member

struct Point {
    i32 x,
    i32 y,
}

trait Measure {
    func size(Point self) -> i32;
}

impl Measure for Point {
    func size(Point self) -> i32 {
        self.x + self.y
    }
}

func total(Point p, Vec[i32] items, i32 index) -> i32 {
    p.size() + items[index]
}
