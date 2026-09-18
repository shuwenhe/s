// M1 Gate: Struct Point Identity Threading Proof

struct Point {
    x: i32
    y: i32
}

func create_point(i32 x, i32 y) Point {
    Point { x: x, y: y }
}

func test_point_identity() {
    p1 := create_point(i32(10), i32(20))
    p2 := create_point(i32(10), i32(20))
}

func main() {
    test_point_identity()
}
