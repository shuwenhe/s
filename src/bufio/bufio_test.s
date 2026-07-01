package src.bufio

func bufio_test_unit_name() string {
    "src/bufio/bufio_test"
}

func bufio_test_unit_ready() int {
    1
}

func bufio_smoke_reader_test() int {
    buffer_reader reader = new_buffer_reader("alpha\nbeta\r\ngamma")
    if reader.peek(5) != "alpha" {
        return 0
    }
    if reader.read_line() != "alpha" {
        return 0
    }
    if reader.read_line() != "beta" {
        return 0
    }
    if reader.read_line() != "gamma" {
        return 0
    }
    if reader.remaining() != 0 {
        return 0
    }
    1
}

func bufio_smoke_writer_test() int {
    buffer_writer writer = new_buffer_writer()
    writer.write("hello")
    writer.write_line("world")
    if writer.contents() != "helloworld\n" {
        return 0
    }
    if writer.len() != 11 {
        return 0
    }
    1
}

func bufio_smoke_round_trip_test() int {
    if buffer_round_trip("line one\nline two") != "line one" {
        return 0
    }
    1
}
