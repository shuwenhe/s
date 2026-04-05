package demo.flow

i32 choose(bool flag, Vec[i32] items, i32 index){
    if flag {
        items[index]
    } else {
        0
    }
}
