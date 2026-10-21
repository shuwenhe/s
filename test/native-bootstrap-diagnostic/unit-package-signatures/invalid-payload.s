package unit_signature_caller
enum payload_check { number(int), text(string) }
func main() int {
    invalid := payload_check.number("wrong type")
    return 0
}
