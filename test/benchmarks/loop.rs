use std::process;

fn main() {
    let mut sum: i64 = 0;
    for i in 1..=20_000_000_i64 {
        sum += i;
    }
    process::exit(sum as i32);
}
