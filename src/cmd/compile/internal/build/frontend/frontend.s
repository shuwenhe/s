package compile.internal.build.frontend

use compile.internal.check.load_frontend

func Load(string path) string {
    return load_frontend(path)
}
