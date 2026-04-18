package demo.prelude

func ok(&string name, &mut vec[int32] items, int32 index) int32 {
    items.push(1);
    name.len() + items.len() + items[index]
}
