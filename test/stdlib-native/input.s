package main
import ("std.input"; "std.prelude")
extern "intrinsic" func host_args() string[]
func main() int {
    args := host_args()
    mode := "keys"
    if len(args) > 1 { mode = args[1] }
    if mode == "notty" {
        ignored, error := std.input.raw_mode(0)
        if error.code != 25 { return 40 }
        return 0
    }
    reader, reader_error := std.input.new_reader(0)
    if reader_error.code != 0 { return reader_error.code }
    if mode == "nonblock" {
        event, error := std.input.read_nonblocking(reader*)
        if error.code != 0 || event.kind != "none" { return 41 }
        return 0
    }
    if mode == "raw-exit" || mode == "raw-explicit" || mode == "raw-error" || mode == "raw-restore-error" {
        session, error := std.input.raw_mode(0)
        if error.code != 0 { return error.code }
        duplicate, duplicate_error := std.input.raw_mode(0)
        if duplicate_error.code != 16 { return 42 }
        println("READY")
        event, read_error := std.input.read_blocking(reader*)
        if mode == "raw-error" {
            if read_error.code != 5 { return 43 }
        } else {
            if read_error.code != 0 || event.code != 113 { return 44 }
        }
        if mode == "raw-restore-error" {
            if std.input.restore(session*).code != 5 || !session.active { return 49 }
            if std.input.restore(session*).code != 0 || session.active { return 50 }
        }
        if mode == "raw-explicit" {
            if std.input.restore(session*).code != 0 { return 45 }
            if std.input.restore(session*).code != 0 { return 46 }
        }
        return 0
    }
    count := 0
    while count < 128 {
        event, error := std.input.read_blocking(reader*)
        if error.code != 0 { return error.code }
        println(event.kind + ":" + std.prelude.to_string(event.code))
        if event.kind == "eof" {
            again, repeated_error := std.input.read_nonblocking(reader*)
            if repeated_error.code != 0 || again.kind != "eof" { return 47 }
            return 0
        }
        count = count + 1
    }
    return 48
}
