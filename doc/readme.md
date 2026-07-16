# S Language

S is an AI-native modern systems language for building compilers, runtimes, kernels, and high-performance infrastructure.

This repository contains the language implementation, standard library, runtime helpers, tests, and build scripts used to exercise the toolchain end to end.

## What is here

- `src/` language and standard library sources
- `lib/` reusable library code
- `api/` public-facing interfaces and generated bindings
- `test/` language and compiler tests
- `doc/` design notes, implementation reports, and plans
- `bin/` helper scripts and utilities
- `run_train.sh` training or demo entrypoint used by the repo

## Quick Start

Build and test the project from the repository root:

```bash
make
```

Run the training or validation script:

```bash
./run_train.sh
```

If you want to work on the compiler or syntax pipeline directly, inspect the code under:

- `src/cmd/compile/`
- `src/runtime/`
- `src/std/`

## Language Notes

- S uses `func` for function declarations.
- S uses modern return-style syntax without `->` in function signatures.
- Package names are path-like and usually map to the source tree layout.
- The standard library favors small, composable modules.

## Contributing

- Keep new code consistent with the existing package layout.
- Prefer adding focused tests near the feature being changed.
- Update the relevant docs in `doc/` when behavior or syntax changes.

## Project Structure

```
s/
├── src/
│   ├── cmd/                    # Compilers and tools
│   │   └── compile/            # S language compiler
│   ├── std/                    # Standard library
│   │   ├── ai/                 # AI/ML modules (tensors, models)
│   │   ├── autograd/           # Automatic differentiation
│   │   ├── nn/                 # Neural network layers
│   │   ├── tensor.s            # Core tensor implementation
│   │   ├── io/                 # I/O operations
│   │   ├── strings/            # String utilities
│   │   └── ...                 # Other modules
│   ├── s/                      # Language core
│   │   ├── ast.s               # Abstract syntax tree
│   │   ├── lexer.s             # Tokenizer
│   │   ├── parser.s            # Parser
│   │   └── ...
│   ├── runtime/                # Runtime support
│   └── builtin/                # Built-in functions
├── lib/                        # Compiled libraries
├── bin/                        # Helper scripts
├── doc/                        # Documentation
├── test/                       # Test suite
├── Makefile                    # Build configuration
└── main.ir                     # Intermediate representation
```

## Language Features

### Modern Function Syntax

```s
// Use 'func' keyword for function declarations
func add(a: int, b: int) int {
    return a + b
}

// Multiple return values without '->'
func divide(a: float, b: float) (float, error) {
    if b == 0.0 {
        return (0.0, error("division by zero"))
    }
    return (a / b, nil)
}

// No return type needed for void functions
func print_status(msg: string) {
    println("Status: " + msg)
}
```

### Standard Library Highlights

- **AI/ML**: Tensor operations, automatic differentiation, neural network modules
- **System**: File I/O, processes, network sockets, system calls
- **Concurrency**: Goroutines, channels, synchronization primitives
- **Data Structures**: Vector, Map, Slice, String, etc.
- **Math**: Linear algebra, mathematical functions, statistics
- **Time**: Time handling, timers, date/time utilities
- **Encoding**: JSON, Protocol Buffers, binary serialization

### Tensor Example

```s
use std.tensor
use std.io

func main() {
    // Create tensors
    var t1 = tensor.zeros([2, 3])
    var t2 = tensor.ones([3, 4])
    
    // Matrix multiplication
    var result = tensor.matmul(t1, t2)
    
    println("Result shape: " + tensor.shape_string(result))
}
```

### Automatic Differentiation

```s
use std.autograd
use std.nn

func main() {
    // Enable gradient tracking
    autograd.enable_gradients(true)
    
    // Create a variable
    var x = autograd.Variable {
        data: [2.0, 3.0],
        requires_grad: true
    }
    
    // Compute function with gradient tracking
    var y = x * x  // y = x²
    
    // Backpropagation
    autograd.backward(y)
    
    // Access gradients: dy/dx = 2x
    println("Gradient: " + autograd.get_grad(x))
}
```

## Compiler Options

### Basic Compilation

```bash
# Compile with default optimization
neurx compile program.s -o program

# Compile with specific optimization level
neurx compile program.s -o program --optimize=0  # No optimization
neurx compile program.s -o program --optimize=1  # Standard optimization
neurx compile program.s -o program --optimize=2  # Aggressive optimization
```

### Advanced Options

```bash
# Emit intermediate representation
neurx compile program.s --emit-ir

# Emit assembly code
neurx compile program.s --emit-asm

# Verbose compilation output
neurx compile program.s -v

# Enable debug information
neurx compile program.s --debug

# Target specific architecture
neurx compile program.s --arch=x86_64
neurx compile program.s --arch=aarch64
```

## Building the Project

### Prerequisites
- S compiler toolchain
- CUDA toolkit (for GPU support, optional)
- Standard build tools (make, etc.)

### Build Steps

```bash
cd /Users/feifei/shuwen/train/s

# Full build
make

# Build specific target
make build
make test
make clean

# View available targets
make help
```

### Running Tests

```bash
# Run all tests
make test

# Run specific test module
neurx test ./src/std/tensor_test.s

# Run with verbose output
make test VERBOSE=1
```

## Performance Characteristics

- **Compilation speed**: Fast incremental compilation
- **Runtime performance**: Near C/C++ performance
- **Memory overhead**: Minimal
- **Startup time**: < 1ms
- **Binary size**: Optimized with dead-code elimination

## Design Philosophy

1. **AI Native**: Purpose-built for AI/ML workloads, not retrofitted
2. **Systems-Level**: Full hardware access, CUDA/GPU support
3. **Modern Design**: Contemporary language features and idioms
4. **Type Safe**: Compile-time error checking, no undefined behavior
5. **Zero-Cost Abstractions**: No runtime overhead for language features

## Development Workflow

### Working on the Compiler

```bash
cd /Users/feifei/shuwen/train/s

# Edit compiler sources in src/cmd/compile/
# Edit runtime in src/runtime/

# Rebuild
make build

# Test your changes
./run_train.sh

# Run compiler tests
make test
```

### Adding New Standard Library Modules

1. Create new module in `src/std/`
2. Implement using S language
3. Add tests in `src/std/*_test.s`
4. Update documentation in `doc/stdlib.md`
5. Export public interfaces in `src/std/*.s`

## Common Tasks

### Debugging Compilation Issues

```bash
# Enable verbose output
neurx compile program.s -v

# Emit IR for inspection
neurx compile program.s --emit-ir > program.ir

# Check syntax without compiling
neurx parse program.s
```

### Profiling Performance

```bash
# Compile with profiling support
neurx compile program.s --profile

# Run with profiling
./program --profile

# Analyze results
neurx profile analyze
```

### Optimization Tips

1. Use `--optimize=2` for production builds
2. Enable inlining for hot functions
3. Use static allocation where possible
4. Leverage vector operations for tensor computations
5. Use channels carefully in concurrent code

## Troubleshooting

### Compilation Errors

- Check for syntax errors: function must use `func` keyword
- Verify return types follow modern syntax (no `->`)
- Ensure all imports are at the top of the file
- Check that types match function signatures

### Runtime Issues

- Enable debug information: `--debug` flag
- Run with stack traces: set `RUST_BACKTRACE=1` environment variable
- Use verbose logging: set `LOGLEVEL=debug`

## Related Documentation

- `doc/spec.md` - Language specification
- `doc/README.md` - Documentation index
- `doc/stdlib.md` - Standard library reference
- `doc/runtime_intrinsics.md` - Runtime intrinsics
- `doc/COMPILER_DESIGN.md` - Compiler architecture
- `doc/OPTIMIZATION_GUIDE.md` - Optimization techniques

## Recent Updates (2026-07-01)

- Standardized all functions to use `func` keyword (no `fn`)
- Removed `->` return type symbols from function signatures
- Updated compiler and standard library for modern syntax
- Enhanced AI/ML module capabilities
- Improved performance optimizations

## Getting Help

- Check existing issues and documentation
- Review examples in `src/std/` modules
- Examine test files for usage patterns
- Consult `doc/` directory for detailed guides

