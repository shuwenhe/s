
fn read_to_string(path: string): string {
    return os.read_file(path)
}

fn write_text_file(path: string, contents: string) {
    os.write_file(path, contents)
}

fn make_temp_dir(prefix: string, base_dir: string = "/app/tmp"): string {
    return os.make_temp_dir(prefix, base_dir)
}
