package demo.flow

func choose(flag: bool, items: Vec[i32], index: i32) -> i32 {
    if flag {
        items[index]
    } else {
        0
    }
}
