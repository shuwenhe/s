package compile.pipeline

struct stage_transition {
    int stage_id
    string name
    string input_artifact
    string output_artifact
    string producer_authority
    string consumer_authority
}

