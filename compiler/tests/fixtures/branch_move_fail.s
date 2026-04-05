package demo.branch

pub fn bad(flag: bool, text: String) -> String {
    if flag {
        text
    } else {
        "alt"
    };
    text
}
