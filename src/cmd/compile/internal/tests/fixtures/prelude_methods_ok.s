package demo.prelude

func ok(&String name, &mut Vec[i32] items, i32 index) -> i32 {
    items.push(1);
    name.len() + items.len() + items[index]
}
