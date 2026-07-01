
func read_to_string(path: string): string {
    return os.read_file(path)
}

func write_text_file(path: string, contents: string) {
    os.write_file(path, contents)
}

func make_temp_dir(prefix: string, base_dir: string = "/app/tmp"): string {
    return os.make_temp_dir(prefix, base_dir)
}
