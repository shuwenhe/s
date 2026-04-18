package compile.internal.build.frontend

use compile.internal.check.load_frontend

func load(string path) string {
    return load_frontend(path)
}
