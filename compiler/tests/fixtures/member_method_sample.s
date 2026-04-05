package demo.member

struct Point {
    x: i32,
    y: i32,
}

trait Measure {
    fn size(self: Point) -> i32;
}

impl Measure for Point {
    fn size(self: Point) -> i32 {
        self.x + self.y
    }
}

fn total(p: Point, items: Vec[i32], index: i32) -> i32 {
    p.size() + items[index]
}
