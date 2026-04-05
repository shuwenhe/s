package demo.conflict

struct Point {
    x: i32,
}

trait MeasureA {
    fn size(self: Point) -> i32;
}

trait MeasureB {
    fn size(self: Point) -> i32;
}

impl MeasureA for Point {
    fn size(self: Point) -> i32 {
        self.x
    }
}

impl MeasureB for Point {
    fn size(self: Point) -> i32 {
        self.x
    }
}

fn bad(p: Point) -> i32 {
    p.size()
}
