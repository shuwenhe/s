package main

import "os"

func main() {
	var sum int64
	for i := int64(1); i <= 20000000; i++ {
		sum += i
	}
	os.Exit(int(sum))
}
