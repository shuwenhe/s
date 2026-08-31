# Integration Guide: Adding --native Flag to S Compiler

## 🎯 Objective

Add `--native` command-line option to S compiler to enable direct machine code generation as an alternative to IR-based compilation.

## 📋 Integration Steps

### Step 1: Modify Main Compiler Entry Point

**File**: `/home/shuwen/shuwen/s/src/cmd/compile/seed/main.s`

Add command-line parsing for `--native` flag:

```s
struct compiler_options {
    string input_file
    string output_file
    bool use_ir
    bool use_native
    bool verbose
    int optimization_level
}

func parse_arguments(string[] args) compiler_options {
    compiler_options opts = {
        input_file: "",
        output_file: "",
        use_ir: true,
        use_native: false,
        verbose: false,
        optimization_level: 0,
    }
    
    int i = 1
    for i < len(args) {
        string arg = args[i]
        
        if arg == "--native" {
            opts.use_ir = false
            opts.use_native = true
        } else if arg == "-O" || arg == "-O2" {
            opts.optimization_level = 2
        } else if arg == "-v" || arg == "--verbose" {
            opts.verbose = true
        } else if arg == "-o" {
            i = i + 1
            if i < len(args) {
                opts.output_file = args[i]
            }
        } else if string_starts_with(arg, "-") {
            # Ignore unknown flags
        } else {
            opts.input_file = arg
        }
        
        i = i + 1
    }
    
    opts
}

func main(string[] args) int {
    compiler_options opts = parse_arguments(args)
    
    if opts.input_file == "" {
        println("Usage: s_seed <input.s> [-o output] [--native]")
        return 1
    }
    
    if opts.use_native {
        # Use new direct code generation
        return compile_native_pipeline(opts.input_file, opts.output_file)
    } else {
        # Use existing IR pipeline
        return compile_ir_pipeline(opts.input_file, opts.output_file)
    }
}
```

---

### Step 2: Create Compiler Router Module

**File**: `/home/shuwen/shuwen/s/src/cmd/compile/seed/router.s`

```s
package compile.router

use compile.ir.pipeline as ir_pipeline
use compile.native.pipeline as native_pipeline

struct compilation_route {
    string mode
    string input_file
    string output_file
    bool debug
}

func route_compilation(string mode, string input, string output) int {
    if mode == "ir" {
        # Existing IR path
        return ir_pipeline.compile_ir(input, output)
    } else if mode == "native" {
        # New native path
        return native_pipeline.compile_native(input, output)
    } else if mode == "auto" {
        # Automatically choose based on context
        return choose_best_method(input, output)
    } else {
        println("Unknown compilation mode: " + mode)
        return 1
    }
}

func choose_best_method(string input, string output) int {
    # Development: use IR for fast feedback
    # Production: use native for performance
    # For now, default to IR
    return ir_pipeline.compile_ir(input, output)
}
```

---

### Step 3: Update Existing IR Pipeline

**File**: `/home/shuwen/shuwen/s/src/cmd/compile/seed/compile_ir.s`

Ensure backward compatibility by making it the default:

```s
func compile_ir_pipeline(string input_file, string output_file) int {
    # Existing compilation logic
    # Unchanged - fully backward compatible
    
    int parse_result = parse_source_file(input_file)
    if parse_result != 0 {
        return parse_result
    }
    
    int codegen_result = generate_ir(output_file)
    if codegen_result != 0 {
        return codegen_result
    }
    
    return 0
}
```

---

### Step 4: Expose Native Pipeline

**File**: `/home/shuwen/shuwen/s/src/cmd/compile/seed/codegen/compile_native.s`

Update main orchestrator:

```s
func compile_native_pipeline(string input_file, string output_file) int {
    print_verbose("Starting native compilation: " + input_file)
    
    # Phase 1: Parse and semantic analysis
    ast* program = parse_source_file(input_file)
    if program == nil {
        println("Parse error in " + input_file)
        return 1
    }
    
    # Phase 2: Type checking
    int type_check = semantic_analysis(program)
    if type_check != 0 {
        println("Type checking failed")
        return type_check
    }
    
    # Phase 3: Generate IR (for now, required for IR->ASM translation)
    ir_program* ir = generate_ir_from_ast(program)
    if ir == nil {
        println("IR generation failed")
        return 1
    }
    
    # Phase 4: Direct code generation (NEW)
    codegen_context ctx = initialize_codegen_context()
    int codegen_result = generate_assembly_from_ir(&ctx, ir)
    if codegen_result != 0 {
        println("Code generation failed")
        return codegen_result
    }
    
    # Phase 5: Output assembly file
    string asm_file = output_file + ".s"
    int asm_result = write_assembly_file(asm_file, &ctx)
    if asm_result != 0 {
        println("Assembly output failed")
        return asm_result
    }
    
    # Phase 6: Assemble and link (NEW)
    compiler_toolchain toolchain = detect_system_toolchain()
    int assemble_result = toolchain.assemble(asm_file, output_file + ".o")
    if assemble_result != 0 {
        println("Assembly failed")
        return assemble_result
    }
    
    int link_result = toolchain.link_executable(output_file + ".o", output_file)
    if link_result != 0 {
        println("Linking failed")
        return link_result
    }
    
    # Cleanup intermediate files
    cleanup_temp_files(asm_file, output_file + ".o")
    
    print_verbose("Native compilation successful: " + output_file)
    return 0
}
```

---

### Step 5: Update Build Configuration

**File**: `/home/shuwen/shuwen/s/src/Makefile` or build script

```makefile
# Add to compilation targets
COMPILER_SOURCES = \
    cmd/compile/seed/main.s \
    cmd/compile/seed/router.s \
    cmd/compile/seed/compile_ir.s \
    cmd/compile/seed/codegen/compile_native.s \
    cmd/compile/seed/codegen/codegen.s \
    cmd/compile/seed/codegen/register.s \
    cmd/compile/seed/codegen/stackframe.s \
    cmd/compile/seed/codegen/instruction_select.s \
    cmd/compile/seed/codegen/linker.s

all: s_seed

s_seed: $(COMPILER_SOURCES)
	s_seed main.s -o $@ --optimize

test-ir:
	./s_seed test/sample.s -o test.ir
	s_ir_runner test.ir

test-native:
	./s_seed test/sample.s --native -o test_native
	./test_native
```

---

### Step 6: Command-Line Interface

After integration, users can compile programs as:

```bash
# IR method (default, fast feedback)
s_seed program.s -o program.ir
s_ir_runner program.ir

# Native method (optimized, production)
s_seed program.s --native -o program
./program

# With optimization
s_seed program.s --native -O2 -o program

# Verbose mode (debugging)
s_seed program.s --native --verbose -o program
```

---

## 🧪 Integration Testing

After implementing integration, test each step:

### Test 1: Argument Parsing
```bash
# Should recognize --native flag
s_seed program.s --native -o output
echo $?  # Should be 0 (success)
```

### Test 2: Mode Routing
```bash
# Should route to native pipeline
s_seed program.s --native -o output
file output  # Should be ELF executable
```

### Test 3: Backward Compatibility
```bash
# Should still work without --native
s_seed program.s -o program.ir
s_ir_runner program.ir  # Should work
```

### Test 4: Full Pipeline
```bash
# End-to-end test
s_seed arithmetic.s --native -o arithmetic
./arithmetic
echo $?  # Should be 3
```

---

## 📊 Integration Progress Checklist

- [ ] Step 1: Modify main.s with argument parsing
  - [ ] Implement parse_arguments()
  - [ ] Add --native flag handling
  - [ ] Route to correct pipeline
  
- [ ] Step 2: Create router module
  - [ ] Implement route_compilation()
  - [ ] Add auto-selection logic
  - [ ] Test routing
  
- [ ] Step 3: Ensure IR backward compatibility
  - [ ] Verify existing tests pass
  - [ ] No breaking changes to IR pipeline
  - [ ] Default behavior unchanged
  
- [ ] Step 4: Expose native pipeline
  - [ ] Implement compile_native_pipeline()
  - [ ] Integrate all codegen modules
  - [ ] Error handling complete
  
- [ ] Step 5: Build system update
  - [ ] All new modules in build
  - [ ] Dependencies correct
  - [ ] No circular imports
  
- [ ] Step 6: Integration tests
  - [ ] Argument parsing works
  - [ ] Mode routing correct
  - [ ] Backward compatible
  - [ ] Full pipeline end-to-end

---

## ⚠️ Key Considerations

### 1. Error Handling
```s
func compile_native_pipeline(...) int {
    # Always check return codes
    if parse_result != 0 { return parse_result }
    if codegen_result != 0 { return codegen_result }
    # Cleanup on any failure
    cleanup_on_error()
}
```

### 2. Temporary Files
```s
func cleanup_temp_files(string asm_file, string obj_file) {
    # Remove intermediate files after successful link
    # Keep them on error for debugging
    if compilation_successful {
        remove_file(asm_file)
        remove_file(obj_file)
    }
}
```

### 3. System Compatibility
```s
func detect_system_toolchain() compiler_toolchain {
    # Detect gcc, ld, as availability
    # Fall back to defaults if not found
    # Validate version compatibility
    compiler_toolchain tc = new compiler_toolchain()
    tc.gcc_path = find_gcc()
    tc.ld_path = find_ld()
    tc.as_path = find_as()
    tc
}
```

### 4. Verbose Output
```s
func print_verbose(string message) {
    if opts.verbose {
        println("[COMPILE] " + message)
    }
}
```

---

## 📈 Performance Expectations After Integration

```
Compilation Pipeline:
  
  IR Mode (default):
    Compile: 100ms
    Run: 800ms
    Total: 900ms
  
  Native Mode (--native):
    Compile: 150ms
    Link: 50ms
    Run: 50ms
    Total: 250ms
  
  Improvement: 3.6x faster end-to-end
```

---

## 🚀 Deployment Path

1. **Phase 1** (Now): Complete testing, integration implemented
2. **Phase 2** (1 week): Validation and performance optimization
3. **Phase 3** (2 weeks): Full test suite compatibility
4. **Phase 4** (3 weeks): Mark as stable
5. **Phase 5** (Optional): Make --native default in future release

---

## 📚 Related Files

- [compile_native.s](./codegen/compile_native.s) - Main entry point
- [codegen.s](./codegen/codegen.s) - Assembly generation
- [register.s](./codegen/register.s) - Register allocation
- [instruction_select.s](./codegen/instruction_select.s) - IR to ASM
- [linker.s](./codegen/linker.s) - Toolchain integration

---

**Status**: Integration plan complete, ready for implementation  
**Estimated Time**: 2-3 days for full integration  
**Complexity**: Medium (mostly module composition)
