package demo.conflict

struct Point {
    i32 x,
}

trait MeasureA {
    func size(Point self) i32;
}

trait MeasureB {
    func size(Point self) i32;
}

impl MeasureA for Point {
    func size(Point self) i32 {
        self.x
    }
}

impl MeasureB for Point {
    func size(Point self) i32 {
        self.x
    }
}

func bad(Point p) i32 {
    p.size()
}
