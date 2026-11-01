package compile.internal.pipeline

struct compilation_artifact {
    string name
    string artifact_type
    string path
    int size_bytes
    string checksum
}

struct artifact_collection {
    compilation_artifact[] artifacts
    string output_directory
}

func artifact_new(string name, string artifact_type, string path) compilation_artifact {
    return compilation_artifact{
        name: name,
        artifact_type: artifact_type,
        path: path,
    }
}

func collection_add(artifact_collection collection, compilation_artifact artifact) {
    collection.artifacts.append(artifact)
}
