package demo.conflict

struct Point {
    int32 x,
}

trait MeasureA {
    func size(Point self) int32;
}

trait MeasureB {
    func size(Point self) int32;
}

impl MeasureA for Point {
    func size(Point self) int32 {
        self.x
    }
}

impl MeasureB for Point {
    func size(Point self) int32 {
        self.x
    }
}

func bad(Point p) int32 {
    p.size()
}
