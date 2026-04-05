package demo.borrow

String bad(i32 value, String text){
    var shared = &value
    var unique = &mut value
    var moved = text
    text
}
