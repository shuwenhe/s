package compile.internal.ssa

use compile.internal.mir.mir_graph
use compile.internal.ssa_core.ssa_program
use compile.internal.ssa_core.build_pipeline as build_pipeline_from_text
use compile.internal.ssa_core.build_pipeline_with_graph_hints
use compile.internal.ssa_core.dump_pipeline
use compile.internal.ssa_core.dump_debug_map

func build_from_text(string mir_text, string arch) ssa_program {
    build_pipeline_from_text(mir_text, arch)
}

func build_from_graph(mir_graph graph, string mir_text, string arch) ssa_program {
    build_pipeline_with_graph_hints(graph, mir_text, arch)
}

func dump(ssa_program program) string {
    dump_pipeline(program)
}

func dump_debug(ssa_program program) string {
    dump_debug_map(program)
}
