// Package: compile.internal.sc
// Module: timing.s
// Description: Compilation timing and performance statistics
// Corresponds to: Go cmd/compile/internal/base.Timer and stats

package compile.internal.sc

import (
    "std.io"
)

// Timer event for tracking compilation phases
struct timer_event {
    string phase_name
    string step_name
    int64 start_ns
    int64 end_ns
    
    func elapsed_ns() int64 {
        return end_ns - start_ns
    }
    
    func elapsed_ms() int64 {
        return elapsed_ns() / 1000000
    }
}

// Compilation phase timing
struct phase_timing {
    string phase_name
    int64 total_ns
    int64 child_ns  // Time spent in child phases
    timer_event[] events
}

// Overall compilation timer
struct compiler_timer {
    int64 start_ns
    int64 end_ns
    phase_timing[] phases
    timer_event[] all_events
}

// Compilation statistics
struct compile_statistics {
    // Counter information
    int num_functions_compiled
    int num_types_processed
    int num_variables
    int num_constants
    
    // Size information  
    int total_code_size_bytes
    int total_data_size_bytes
    int ir_size_bytes
    int ssa_size_bytes
    
    // Optimization information
    int functions_inlined
    int functions_inlined_count  // Total inlines (same func inlined multiple times counts multiple)
    int escape_to_heap_count
    int escape_to_global_count
    
    // Timing information
    int64 total_time_ns
    int64 parse_time_ns
    int64 semantic_time_ns
    int64 optimize_time_ns
    int64 codegen_time_ns
    
    // Error/warning information
    int num_errors
    int num_warnings
}

// Initialize compiler timer
func timer_new() compiler_timer {
    return compiler_timer{
        start_ns: __runtime_nanotime(),
        end_ns: 0,
        phases: phase_timing[]{},
        all_events: timer_event[]{},
    }
}

// Start a new phase
func timer_start_phase(compiler_timer t, string phase_name, string step_name) timer_event {
    event := timer_event{
        phase_name: phase_name,
        step_name: step_name,
        start_ns: __runtime_nanotime(),
        end_ns: 0,
    }
    
    return event
}

// End a phase and record timing
func timer_end_phase(compiler_timer t, timer_event event) {
    event.end_ns = __runtime_nanotime()
    
    // Record in all_events
    t.all_events.append(event)
    
    // Update phase timing
    found := false
    i := 0
    while i < len(t.phases) {
        if t.phases[i].phase_name == event.phase_name {
            t.phases[i].total_ns = t.phases[i].total_ns + event.elapsed_ns()
            t.phases[i].events.append(event)
            found = true
            break
        }
        i = i + 1
    }
    
    if !found {
        t.phases.append(phase_timing{
            phase_name: event.phase_name,
            total_ns: event.elapsed_ns(),
            events: timer_event[]{ event },
        })
    }
}

// Finalize timer and return statistics
func timer_finalize(compiler_timer t) compile_statistics {
    t.end_ns = __runtime_nanotime()
    
    stats := compile_statistics{
        total_time_ns: t.end_ns - t.start_ns,
    }
    
    return stats
}

// Print timing information
func timer_print(compiler_timer t, any output) {
    total_ms := (t.end_ns - t.start_ns) / 1000000
    
    std.io.eprintln("")
    std.io.eprintln("=== Compilation Timing ===")
    std.io.eprintln("Total time: " + std.conv.fmt_int(total_ms) + "ms")
    std.io.eprintln("")
    std.io.eprintln("Phase breakdown:")
    
    i := 0
    while i < len(t.phases) {
        phase := t.phases[i]
        phase_ms := phase.total_ns / 1000000
        percent := (phase.total_ns * 100) / (t.end_ns - t.start_ns)
        
        std.io.eprintln("  " + phase.phase_name + ": " + std.conv.fmt_int(phase_ms) + "ms (" + std.conv.fmt_int(percent) + "%)")
        
        j := 0
        while j < len(phase.events) {
            event := phase.events[j]
            event_ms := event.elapsed_ns() / 1000000
            std.io.eprintln("    - " + event.step_name + ": " + std.conv.fmt_int(event_ms) + "ms")
            j = j + 1
        }
        
        i = i + 1
    }
}

// Initialize statistics collector
func stats_new() compile_statistics {
    return compile_statistics{
        num_functions_compiled: 0,
        num_types_processed: 0,
        num_variables: 0,
        num_constants: 0,
        total_code_size_bytes: 0,
        total_data_size_bytes: 0,
        num_errors: 0,
        num_warnings: 0,
    }
}

// Record function compilation
func stats_add_function(compile_statistics stats, string func_name, int code_size) {
    stats.num_functions_compiled = stats.num_functions_compiled + 1
    stats.total_code_size_bytes = stats.total_code_size_bytes + code_size
}

// Record type processing
func stats_add_type(compile_statistics stats, string type_name, int data_size) {
    stats.num_types_processed = stats.num_types_processed + 1
    stats.total_data_size_bytes = stats.total_data_size_bytes + data_size
}

// Record optimization
func stats_record_inlining(compile_statistics stats, int count) {
    stats.functions_inlined_count = stats.functions_inlined_count + count
}

// Print statistics
func stats_print(compile_statistics stats) {
    std.io.eprintln("")
    std.io.eprintln("=== Compilation Statistics ===")
    std.io.eprintln("Functions compiled: " + std.conv.fmt_int(stats.num_functions_compiled))
    std.io.eprintln("Types processed: " + std.conv.fmt_int(stats.num_types_processed))
    std.io.eprintln("Code size: " + std.conv.fmt_int(stats.total_code_size_bytes) + " bytes")
    std.io.eprintln("Data size: " + std.conv.fmt_int(stats.total_data_size_bytes) + " bytes")
    
    if stats.functions_inlined_count > 0 {
        std.io.eprintln("Inlines: " + std.conv.fmt_int(stats.functions_inlined_count))
    }
    
    if stats.num_errors > 0 {
        std.io.eprintln("Errors: " + std.conv.fmt_int(stats.num_errors))
    }
    
    if stats.num_warnings > 0 {
        std.io.eprintln("Warnings: " + std.conv.fmt_int(stats.num_warnings))
    }
    
    std.io.eprintln("")
}

// Merge multiple statistics
func stats_merge(compile_statistics[] stats_list) compile_statistics {
    merged := stats_new()
    
    i := 0
    while i < len(stats_list) {
        s := stats_list[i]
        merged.num_functions_compiled = merged.num_functions_compiled + s.num_functions_compiled
        merged.num_types_processed = merged.num_types_processed + s.num_types_processed
        merged.total_code_size_bytes = merged.total_code_size_bytes + s.total_code_size_bytes
        merged.total_data_size_bytes = merged.total_data_size_bytes + s.total_data_size_bytes
        merged.num_errors = merged.num_errors + s.num_errors
        merged.num_warnings = merged.num_warnings + s.num_warnings
        i = i + 1
    }
    
    return merged
}
