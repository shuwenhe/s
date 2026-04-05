package demo.conflict

struct Point {
    x: i32,
}

trait MeasureA {
    func size(self: Point) -> i32;
}

trait MeasureB {
    func size(self: Point) -> i32;
}

impl MeasureA for Point {
    func size(self: Point) -> i32 {
        self.x
    }
}

impl MeasureB for Point {
    func size(self: Point) -> i32 {
        self.x
    }
}

func bad(p: Point) -> i32 {
    p.size()
}
