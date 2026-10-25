package compile.internal.pipeline

enum compilation_stage {
    STAGE_INIT: = 0,
    STAGE_PARSE: = 1,
    STAGE_SEMANTIC: = 2,
    STAGE_OPTIMIZE: = 3,
    STAGE_LOWER: = 4,
    STAGE_MIDDLEND: = 5,
    STAGE_BACKEND: = 6,
    STAGE_OUTPUT: = 7,
}

struct stage_info {
    compilation_stage stage
    string stage_name
    string description
    int64 start_time
    int64 end_time
}

func stage_name_str(compilation_stage stage) string {
    if stage == compilation_stage.STAGE_PARSE {
        return "Parse"
    } else if stage == compilation_stage.STAGE_SEMANTIC {
        return "Semantic"
    } else if stage == compilation_stage.STAGE_OPTIMIZE {
        return "Optimize"
    } else if stage == compilation_stage.STAGE_LOWER {
        return "Lower"
    } else if stage == compilation_stage.STAGE_MIDDLEND {
        return "Middlend"
    } else if stage == compilation_stage.STAGE_BACKEND {
        return "Backend"
    } else if stage == compilation_stage.STAGE_OUTPUT {
        return "Output"
    }
    return "Unknown"
}
