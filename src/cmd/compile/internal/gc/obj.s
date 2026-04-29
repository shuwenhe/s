package compile.internal.gc

func mode_compiler_obj() int {
    1
}

func mode_linker_obj() int {
    2
}

func dump_object_bundle(string pkg_name, string compiler_payload, string linker_payload, int mode) string {
    let out = "!<arch>\n"
    if (mode & mode_compiler_obj()) != 0 {
        out = out + "__.PKGDEF\n"
        out = out + "package=" + pkg_name + "\n"
        out = out + compiler_payload + "\n"
    }
    if (mode & mode_linker_obj()) != 0 {
        out = out + "_go_.o\n"
        out = out + linker_payload + "\n"
    }
    out
}
