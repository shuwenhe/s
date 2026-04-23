package compile.internal.build.cache

use std.fs.read_to_string
use std.fs.write_text_file
use std.prelude.len
use std.prelude.slice
use std.prelude.to_string

func cache_hit(string source_path, string source_text, string phase) bool {
    var stamp_path = source_path + "." + phase + ".cache"
    var cached = read_to_string(stamp_path)
    if cached.is_err() {
        return false
    }
    cached.unwrap() == fingerprint(source_text)
}

func update_cache(string source_path, string source_text, string phase) bool {
    var stamp_path = source_path + "." + phase + ".cache"
    var write = write_text_file(stamp_path, fingerprint(source_text))
    !write.is_err()
}

func fingerprint(string source_text) string {
    var funcs = count_token(source_text, "func ")
    var structs = count_token(source_text, "struct ")
    var calls = count_token(source_text, " call")
    to_string(len(source_text)) + ":" + to_string(funcs) + ":" + to_string(structs) + ":" + to_string(calls)
}

func count_token(string text, string token) int32 {
    if token == "" {
        return 0
    }

    var total = 0
    var i = 0
    while i <= len(text) - len(token) {
        if slice(text, i, i + len(token)) == token {
            total = total + 1
            i = i + len(token)
        } else {
            i = i + 1
        }
    }
    total
}
