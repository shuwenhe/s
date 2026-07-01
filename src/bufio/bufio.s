package src.bufio

struct buffer_reader {
    string data
    int offset
}

struct buffer_writer {
    string data
}

func bufio_unit_name() string {
    "src/bufio/bufio"
}

func bufio_unit_ready() int {
    1
}

func new_buffer_reader(string data) buffer_reader {
    buffer_reader {
        data: data,
        offset: 0,
    }
}

func new_buffer_writer() buffer_writer {
    buffer_writer {
        data: "",
    }
}

func clamp_buffer_end(string data, int start, int requested_end) int {
    int end = requested_end
    int begin = start
    if begin < 0 {
        begin = 0
    }
    if end < begin {
        end = begin
    }
    if end > len(data) {
        end = len(data)
    }
    end
}

func trim_trailing_cr(string line) string {
    if len(line) > 0 && slice(line, len(line) - 1, len(line)) == "\r" {
        slice(line, 0, len(line) - 1)
    } else {
        line
    }
}

func (r *buffer_reader) remaining() int {
    if r.offset >= len(r.data) {
        return 0
    }
    len(r.data) - r.offset
}

func (r *buffer_reader) peek(int n) string {
    int end = clamp_buffer_end(r.data, r.offset, r.offset + n)
    slice(r.data, r.offset, end)
}

func (r *buffer_reader) read(int n) string {
    string chunk = r.peek(n)
    r.offset = r.offset + len(chunk)
    chunk
}

func (r *buffer_reader) read_byte() string {
    r.read(1)
}

func (r *buffer_reader) read_line() string {
    if r.offset >= len(r.data) {
        return ""
    }

    int start = r.offset
    while r.offset < len(r.data) {
        if slice(r.data, r.offset, r.offset + 1) == "\n" {
            string line = slice(r.data, start, r.offset)
            r.offset = r.offset + 1
            return trim_trailing_cr(line)
        }
        r.offset = r.offset + 1
    }

    trim_trailing_cr(slice(r.data, start, len(r.data)))
}

func (r *buffer_reader) reset() {
    r.offset = 0
}

func (w *buffer_writer) write(string chunk) {
    w.data = w.data + chunk
}

func (w *buffer_writer) write_line(string line) {
    w.data = w.data + line + "\n"
}

func (w *buffer_writer) contents() string {
    w.data
}

func (w *buffer_writer) len() int {
    len(w.data)
}

func (w *buffer_writer) reset() {
    w.data = ""
}

func buffer_read_first_line(string text) string {
    buffer_reader reader = new_buffer_reader(text)
    reader.read_line()
}

func buffer_round_trip(string input) string {
    buffer_reader reader = new_buffer_reader(input)
    buffer_writer writer = new_buffer_writer()
    writer.write(reader.read_line())
    writer.contents()
}
