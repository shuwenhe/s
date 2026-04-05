package demo.prelude

i32 ok(&String name, &mut Vec[i32] items, i32 index) {
    items.push(1);
    name.len() + items.len() + items[index]
}
