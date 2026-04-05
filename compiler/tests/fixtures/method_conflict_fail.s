package demo.conflict

struct Point {
    i32 x,
}

trait MeasureA {
    i32 size(Point self);
}

trait MeasureB {
    i32 size(Point self);
}

impl MeasureA for Point {
    i32 size(Point self){
        self.x
    }
}

impl MeasureB for Point {
    i32 size(Point self){
        self.x
    }
}

i32 bad(Point p){
    p.size()
}
