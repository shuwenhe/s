package demo.prelude

func ok(&string name, &vec[int] items, int index) int {
    items.push(1);
    name.len() + items.len() + items[index]
}
