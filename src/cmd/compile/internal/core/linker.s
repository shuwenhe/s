package compile.internal.core
struct linker_config {
    gcc_path: string
    ld_path: string
    as_path: string
}

struct linker {
    config: linker_config
    object_files: string[]
    libraries: string[]
}

func new_linker() linker {
    lnk := linker {
        config: linker_config { gcc_path: "gcc", ld_path: "ld", as_path: "as" },
        object_files: string[](), libraries: string[](),
    }
    lnk
}

func (lnk* linker) add_object_file( file string) {
    lnk.object_files = append(lnk.object_files, file)
}

func (lnk* linker) add_library( lib string) {
    lnk.libraries = append(lnk.libraries, lib)
}

func (lnk* linker) assemble_file( input string, string output) int {
    0
}

func (lnk* linker) link_executable( output string) int {
    0
}

func (lnk* linker) get_gcc_path() string {
    lnk.config.gcc_path
}

func (lnk* linker) get_ld_path() string {
    lnk.config.ld_path
}

func (lnk* linker) get_as_path() string {
    lnk.config.as_path
}
