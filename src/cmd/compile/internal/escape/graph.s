package compile.internal.escape

enum escape_level {
    escape_none,
    escape_func,
    escape_global,
    escape_heap,
}

struct leaks {
    int heap
    int result
    int mutator
    int callee
}

struct leak_summary {
    int heap
    int result
    int mutator
    int callee
}

struct escape_location {
    int id
    string name
    bool heap
}

struct escape_edge {
    int from
    int to
    int derefs
    string reason
}

struct escape_graph {
    escape_location[] locations
    escape_edge[] edges
}

struct escape_info {
    int variable_id
    int level
    bool is_pointer
    bool address_taken
    bool returned
    bool stored_global
    bool stored_heap
    string reason
}

struct escape_analysis {
    escape_info[] infos
    escape_graph graph
    leak_summary leaks
}

func new_escape_graph() escape_graph {
    escape_graph {}
}

func add_escape_location(escape_graph g, int id, string name) int {
    id
}

func add_escape_edge(escape_graph g, int from, int to, int derefs, string reason) {
}

func mark_escape_heap(escape_graph g, int id) {
}

func escape_graph_heap_count(escape_graph graph) int {
    len(graph.locations)
}
