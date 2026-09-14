package compile.internal.ssa
import (
    "compile.internal.mir"
    "compile.internal.ssa_core"
)
func build_from_text(string mir_text, string arch) ssa_program {
    build_pipeline_from_text(mir_text, arch)
}

func build_from_graph(mir_graph graph, string mir_text, string arch) ssa_program {
    compile.internal.ssa_core.build_pipeline_with_graph_hints(graph, mir_text, arch)
}

func dump(ssa_program program) string {
    compile.internal.ssa_core.dump_pipeline(program)
}

func dump_debug(ssa_program program) string {
