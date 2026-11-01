#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-fs-result.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo "fs result artifacts: $work" >&2; fi' EXIT
cat > "$work/main.s" <<'S'
package main
import "std.fs"
func main() int {
    args := host_args()
    path := args[1]
    ignored, write_error := fs.write_text_file(path, "native data")
    if write_error.message != "" { return 1 }
    text, read_error := fs.read_to_string(path)
    if read_error.message != "" || text != "native data" { return 2 }
    missing, missing_error := fs.read_to_string(path + "/missing")
    if missing_error.message == "" { return 3 }
    ignored_again, bad_write := fs.write_text_file(path + "/missing", "no")
    if bad_write.message == "" { return 4 }
    empty_write, empty_error := fs.write_text_file(path, "")
    if empty_error.message != "" { return 5 }
    empty, empty_read_error := fs.read_to_string(path)
    if empty != "" || empty_read_error.message != "" { return 6 }
    directory, temp_error := fs.make_temp_dir(args[2])
    if directory == "" || temp_error.message != "" { return 7 }
    bad_directory, bad_temp := fs.make_temp_dir(path)
    if bad_temp.message == "" { return 8 }
    return 42
}
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$root/src/result/result.s" "$root/src/fs/fs.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" "$work/data" "$work" || status=$?
echo "native fs program status: $status"
test "$status" -eq 42
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/main"
echo 'native fs result success, failure, empty file and directory: PASS'

# An extern return annotation cannot authorize a different runtime layout.
sed 's/NOP|record-field:std.fs.fs_error|message|string/NOP|record-field:std.fs.fs_error|message|int/' "$work/main.ir" > "$work/forged.ir"
printf 'preserve\n' > "$work/preserve"
cp "$work/preserve" "$work/saved"
if S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/forged.ir" "$work/preserve" > "$work/forged.log" 2>&1; then
    echo 'accepted forged filesystem result schema' >&2; exit 1
fi
cmp "$work/preserve" "$work/saved"
echo 'native filesystem result schema forgery rejected: PASS'
