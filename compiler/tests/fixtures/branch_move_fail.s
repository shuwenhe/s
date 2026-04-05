package demo.branch

func bad(flag: bool, text: String) -> String {
    if flag {
        text
    } else {
        "alt"
    };
    text
}
