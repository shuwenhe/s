package backend
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
    lnk: linker
    lnk.config.gcc_path = "gcc"
    lnk.config.ld_path = "ld"
    lnk.config.as_path = "as"
    lnk.object_files = make(string[])
    lnk.libraries = make(string[])
    lnk
}

func (lnk* linker) add_object_file( file string) {
    lnk.object_files = append(lnk.object_files, file)
}

func (lnk* linker) add_library( lib string) {
    lnk.libraries = append(lnk.libraries, lib)
}

func (lnk* linker) assemble_file( input string, output string) int {
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
