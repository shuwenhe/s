package compile.internal.build.frontend

use compile.internal.check.LoadFrontend

func Load(String path) -> String {
    return LoadFrontend(path)
}
