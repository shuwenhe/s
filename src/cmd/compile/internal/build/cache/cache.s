package compile.internal.build.cache

use std.fs.read_to_string
use std.fs.write_text_file
use std.prelude.len
use std.prelude.slice
use std.prelude.to_string

struct dep_version_state {
    int32 version
    int32 depth
    int32 layer_epoch
}

struct dep_graph_state {
    int32 max_depth
    int32 epoch_acc
    int32 dep_count
    string direct_signature
}

func cache_hit(string source_path, string source_text, string phase) bool {
    cache_hit_target(source_path, source_text, phase, "default")
}

func cache_hit_target(string source_path, string source_text, string phase, string target_key) bool {
    var stamp_path = cache_stamp_path(source_path, phase, target_key)
    var cached = read_to_string(stamp_path)
    if cached.is_err() {
        return false
    }
    cached.unwrap() == dependency_fingerprint(source_path, source_text, phase, target_key)
}

func update_cache(string source_path, string source_text, string phase) bool {
    update_cache_target(source_path, source_text, phase, "default")
}

func update_cache_target(string source_path, string source_text, string phase, string target_key) bool {
    var stamp_path = cache_stamp_path(source_path, phase, target_key)
    var domain = invalidation_domain(source_path, source_text, phase, target_key)
    var previous = read_to_string(stamp_path)
    var next_fingerprint = dependency_fingerprint(source_path, source_text, phase, target_key)
    var write = write_text_file(stamp_path, next_fingerprint)
    if write.is_err() {
        return false
    }

    if previous.is_err() || previous.unwrap() != next_fingerprint {
        var ignored_epoch = bump_phase_epoch(phase, domain)
    }

    var pkg = package_name(source_text)
    var prev_export = read_to_string(export_stamp_path(pkg))
    var next_export = export_signature(source_text)
    var prev_state = read_dep_version_state(pkg)
    var next_version = prev_state.version
    if prev_export.is_err() || prev_export.unwrap() != next_export {
        next_version = next_version + 1
    }

    var graph_state = dependency_graph_state(source_text)
    var next_depth = graph_state.max_depth + 1
    if next_depth < 1 {
        next_depth = 1
    }
    var next_layer_epoch = next_version * 97 + next_depth * 13 + graph_state.epoch_acc + graph_state.dep_count

    var export_stamp = export_stamp_path(pkg)
    var export_write = write_text_file(export_stamp, next_export)
    if export_write.is_err() {
        return false
    }

    var version_stamp = version_stamp_path(pkg)
    var version_payload = "version=" + to_string(next_version)
        + ";depth=" + to_string(next_depth)
        + ";layer=" + to_string(next_layer_epoch)
        + ";phase_epoch=" + to_string(read_phase_epoch(phase, domain))
        + ";target=" + sanitize_key(target_key)
        + ";deps=" + graph_state.direct_signature
    var version_write = write_text_file(version_stamp, version_payload)
    !version_write.is_err()
}

func dependency_fingerprint(string source_path, string source_text, string phase, string target_key) string {
    var own = fingerprint(source_text)
    var pkg = package_name(source_text)
    var imports = import_signature(source_text)
    var exports = export_signature(source_text)
    var propagated = dependency_layer_version_signature(source_text)
    var domain = invalidation_domain(source_path, source_text, phase, target_key)
    var epoch = read_phase_epoch(phase, domain)
    phase + ":" + source_path + ":" + pkg + ":" + own + ":" + imports + ":" + exports + ":" + propagated + ":domain=" + domain + ":epoch=" + to_string(epoch) + ":target=" + sanitize_key(target_key)
}

func cache_stamp_path(string source_path, string phase, string target_key) string {
    source_path + "." + phase + "." + sanitize_key(target_key) + ".cache"
}

func invalidation_domain(string source_path, string source_text, string phase, string target_key) string {
    var pkg = package_name(source_text)
    phase + ":" + pkg + ":" + sanitize_key(source_path) + ":" + sanitize_key(target_key)
}

func phase_stamp_path(string phase, string domain) string {
    ".s.cache.phase." + sanitize_key(phase) + "." + sanitize_key(domain)
}

func read_phase_epoch(string phase, string domain) int32 {
    var stamp = read_to_string(phase_stamp_path(phase, domain))
    if stamp.is_err() {
        return 0
    }
    var value = parse_field_int(stamp.unwrap(), "epoch=")
    if value < 0 {
        return 0
    }
    value
}

func bump_phase_epoch(string phase, string domain) bool {
    var current = read_phase_epoch(phase, domain)
    var next = current + 1
    var payload = "epoch=" + to_string(next)
    var write = write_text_file(phase_stamp_path(phase, domain), payload)
    !write.is_err()
}

func fingerprint(string source_text) string {
    var funcs = count_token(source_text, "func ")
    var structs = count_token(source_text, "struct ")
    var calls = count_token(source_text, " call")
    var uses = count_token(source_text, "\nuse ")
    var pkg = package_name(source_text)
    pkg + ":" + to_string(len(source_text)) + ":" + to_string(funcs) + ":" + to_string(structs) + ":" + to_string(calls) + ":" + to_string(uses)
}

func import_signature(string source_text) string {
    var sig = "imports"
    var cursor = 0
    while cursor < len(source_text) {
        var line_end = index_of_from(source_text, "\n", cursor)
        if line_end < 0 {
            line_end = len(source_text)
        }
        var line = trim_spaces(slice(source_text, cursor, line_end))
        if starts_with(line, "use ") {
            var path = use_path_from_line(line)
            sig = sig + "|" + path
        }
        cursor = line_end + 1
    }
    sig
}

func export_signature(string source_text) string {
    var pub_funcs = count_token(source_text, "\npub func ") + count_token(source_text, "\npub\nfunc ")
    var pub_structs = count_token(source_text, "\npub struct ")
    var pub_enums = count_token(source_text, "\npub enum ")
    var pub_traits = count_token(source_text, "\npub trait ")
    var pub_impls = count_token(source_text, "\npub impl ")
    "exports:" + to_string(pub_funcs) + ":" + to_string(pub_structs) + ":" + to_string(pub_enums) + ":" + to_string(pub_traits) + ":" + to_string(pub_impls)
}

func dependency_layer_version_signature(string source_text) string {
    var graph = dependency_graph_state(source_text)
    var sig = "dep-layer"
        + ":max_depth=" + to_string(graph.max_depth)
        + ":epoch=" + to_string(graph.epoch_acc)
        + ":count=" + to_string(graph.dep_count)
        + ":direct=" + graph.direct_signature
    sig
}

func dependency_graph_state(string source_text) dep_graph_state {
    var max_depth = 0
    var epoch_acc = 0
    var dep_count = 0
    var direct_signature = ""
    var cursor = 0
    while cursor < len(source_text) {
        var line_end = index_of_from(source_text, "\n", cursor)
        if line_end < 0 {
            line_end = len(source_text)
        }
        var line = trim_spaces(slice(source_text, cursor, line_end))
        if starts_with(line, "use ") {
            var path = use_path_from_line(line)
            var dep_state = read_dep_version_state(path)
            if dep_state.depth > max_depth {
                max_depth = dep_state.depth
            }
            var weighted = dep_state.layer_epoch + dep_state.version * (dep_state.depth + 1)
            epoch_acc = epoch_acc + weighted
            dep_count = dep_count + 1
            direct_signature = direct_signature
                + "|" + path
                + "@v" + to_string(dep_state.version)
                + "d" + to_string(dep_state.depth)
                + "l" + to_string(dep_state.layer_epoch)
        }
        cursor = line_end + 1
    }

    dep_graph_state {
        max_depth: max_depth,
        epoch_acc: epoch_acc,
        dep_count: dep_count,
        direct_signature: direct_signature,
    }
}

func export_stamp_path(string pkg_or_use_path) string {
    ".s.cache.export." + sanitize_key(pkg_or_use_path)
}

func version_stamp_path(string pkg_or_use_path) string {
    ".s.cache.version." + sanitize_key(pkg_or_use_path)
}

func read_dep_version_state(string pkg_or_use_path) dep_version_state {
    var stamp = read_to_string(version_stamp_path(pkg_or_use_path))
    if stamp.is_err() {
        return dep_version_state {
            version: 0,
            depth: 0,
            layer_epoch: 0,
        }
    }

    var text = stamp.unwrap()
    var version = parse_field_int(text, "version=")
    var depth = parse_field_int(text, "depth=")
    var layer = parse_field_int(text, "layer=")
    if version < 0 {
        version = 0
    }
    if depth < 0 {
        depth = 0
    }
    if layer < 0 {
        layer = 0
    }

    dep_version_state {
        version: version,
        depth: depth,
        layer_epoch: layer,
    }
}

func parse_field_int(string text, string marker) int32 {
    var start = index_of(text, marker)
    if start < 0 {
        return -1
    }
    start = start + len(marker)
    var value = 0
    var seen = false
    while start < len(text) {
        var ch = slice(text, start, start + 1)
        if ch < "0" || ch > "9" {
            break
        }
        value = value * 10 + digit_value(ch)
        seen = true
        start = start + 1
    }
    if !seen {
        return -1
    }
    value
}

func digit_value(string ch) int32 {
    if ch == "0" { return 0 }
    if ch == "1" { return 1 }
    if ch == "2" { return 2 }
    if ch == "3" { return 3 }
    if ch == "4" { return 4 }
    if ch == "5" { return 5 }
    if ch == "6" { return 6 }
    if ch == "7" { return 7 }
    if ch == "8" { return 8 }
    if ch == "9" { return 9 }
    0
}

func sanitize_key(string text) string {
    var out = ""
    var i = 0
    while i < len(text) {
        var ch = slice(text, i, i + 1)
        if ch == "." || ch == "/" || ch == " " || ch == "\t" || ch == "\n" || ch == "\r" {
            out = out + "_"
        } else {
            out = out + ch
        }
        i = i + 1
    }
    out
}

func use_path_from_line(string line) string {
    var payload = trim_spaces(slice(line, 4, len(line)))
    var as_pos = index_of(payload, " as ")
    if as_pos < 0 {
        return payload
    }
    trim_spaces(slice(payload, 0, as_pos))
}

func trim_spaces(string text) string {
    var start = 0
    var end = len(text)
    while start < end {
        var ch0 = slice(text, start, start + 1)
        if ch0 != " " && ch0 != "\t" && ch0 != "\n" && ch0 != "\r" {
            break
        }
        start = start + 1
    }
    while end > start {
        var ch1 = slice(text, end - 1, end)
        if ch1 != " " && ch1 != "\t" && ch1 != "\n" && ch1 != "\r" {
            break
        }
        end = end - 1
    }
    slice(text, start, end)
}

func starts_with(string text, string prefix) bool {
    if len(prefix) > len(text) {
        return false
    }
    slice(text, 0, len(prefix)) == prefix
}

func package_name(string source_text) string {
    var marker = "package "
    var start = index_of(source_text, marker)
    if start < 0 {
        return "unknown"
    }
    start = start + len(marker)
    var end = start
    while end < len(source_text) {
        var ch = slice(source_text, end, end + 1)
        if ch == " " || ch == "\n" || ch == "\r" || ch == "\t" {
            break
        }
        end = end + 1
    }
    slice(source_text, start, end)
}

func index_of(string text, string token) int32 {
    if token == "" {
        return 0
    }
    var i = 0
    while i <= len(text) - len(token) {
        if slice(text, i, i + len(token)) == token {
            return i
        }
        i = i + 1
    }
    -1
}

func index_of_from(string text, string token, int32 start) int32 {
    if token == "" {
        return start
    }
    var i = start
    while i <= len(text) - len(token) {
        if slice(text, i, i + len(token)) == token {
            return i
        }
        i = i + 1
    }
    -1
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
