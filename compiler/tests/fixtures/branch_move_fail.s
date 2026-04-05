package demo.branch

fn bad(flag: bool, text: String) -> String {
    if flag {
        text
    } else {
        "alt"
    };
    text
}
