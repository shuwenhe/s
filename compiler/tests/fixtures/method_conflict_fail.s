package demo.conflict

pub struct Point {
    x: i32,
}

pub trait MeasureA {
    fn size(self: Point) -> i32;
}

pub trait MeasureB {
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

pub fn bad(p: Point) -> i32 {
    p.size()
}
