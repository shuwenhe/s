package demo.member

struct Point {
    i32 x,
    i32 y,
}

trait Measure {
    i32 size(Point self);
}

impl Measure for Point {
    i32 size(Point self){
        self.x + self.y
    }
}

i32 total(Point p, Vec[i32] items, i32 index){
    p.size() + items[index]
}
