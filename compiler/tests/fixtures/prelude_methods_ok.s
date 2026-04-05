package demo.prelude

fn ok(name: &String, items: &mut Vec[i32], index: i32) -> i32 {
    items.push(1);
    name.len() + items.len() + items[index]
}
