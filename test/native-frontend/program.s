package sample.native

func main(int input) int {
    local := later(input + 3)
    int rebound = local * 2
    rebound = rebound - 1
    return rebound / 2 % 31
}

func unused(int first, int second) int { return first - second }
func later(int value) int { effect(); return final(value, -(2 + 1)) }
func effect() () {}
func final(int left, int right) int { return left + right }
