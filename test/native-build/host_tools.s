package native_host_tools_test
extern "intrinsic" func __host_run_argv(string[] args) int
extern "intrinsic" func __host_same_file(string left, string right) bool
extern "intrinsic" func __host_rename_file(string from, string to) int
extern "intrinsic" func __host_make_temp_dir_in(string directory) string
extern "intrinsic" func __host_write_text_file(string path, string text) int
extern "intrinsic" func __host_read_to_string(string path) string
extern "intrinsic" func host_args() string[]
func main() int {
    args := host_args()
    if len(args) != 3 { return 1 }
    tool := args[1]
    work := args[2]
    if __host_run_argv([tool, "a b", "$(touch injected)", "quote'\";"]) != 7 { return 2 }
    if __host_run_argv([tool, "success"]) != 0 { return 3 }
    if __host_run_argv([tool, "signal"]) != 143 { return 4 }
    missing := work + "/absent"
    if __host_run_argv([missing]) != 127 { return 5 }
    if __host_run_argv(string[]()) != -1 { return 6 }
    if __host_write_text_file(work + "/from", "native host tools") != 0 { return 7 }
    if !__host_same_file(work + "/from", work + "/./from") { return 8 }
    if __host_same_file(work + "/from", work + "/not-created") { return 9 }
    if __host_rename_file(work + "/from", work + "/to") != 0 { return 10 }
    if __host_read_to_string(work + "/to") != "native host tools" { return 11 }
    if __host_rename_file(work + "/absent", work + "/to") == 0 { return 12 }
    temporary := __host_make_temp_dir_in(work)
    if temporary == "" { return 13 }
    if __host_write_text_file(temporary + "/probe", "same filesystem") != 0 { return 14 }
    if __host_rename_file(temporary + "/probe", work + "/installed") != 0 { return 15 }
    return 0
}
