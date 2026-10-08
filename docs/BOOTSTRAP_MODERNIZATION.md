# S Compiler Bootstrap Modernization

## Overview

This document describes the transition from **manifest-based bootstrap** to **import-driven bootstrap** in the S compiler, following Go's compiler architecture.

## The Problem with Manifest Files

### Current Approach (manifest-based)
```
selfhost-sources.txt → materialize-selfhost-source.sh → pasted source → compiled
```

**Issues:**
1. **Manual maintenance** - Must manually list all source files
2. **Error-prone** - Easy to forget files or list them in wrong order
3. **Not declarative** - Dependencies are external, not in code
4. **Not scalable** - Hard to add conditional compilation (platform-specific code)
5. **IDE unfriendly** - IDE cannot understand the manifest format

### New Approach (import-driven)
```
selfhost/main.s (imports) → seed compiler trace imports → auto-discovered packages → compiled
```

**Advantages:**
1. **Automatic discovery** - Seed compiler traces imports
2. **Declarative** - Dependencies are in code (import statements)
3. **Compiler-enforced** - Missing imports cause compilation errors
4. **IDE compatible** - Standard S import syntax
5. **Follows Go model** - Proven industrial approach

## Architecture

### New Selfhost Package Structure

```
src/cmd/compile/selfhost/
├── main.s                    # Entry point with all imports
├── frontend.s                # Aggregates frontend components
├── middlend.s                # Aggregates middlend components
└── backend.s                 # Aggregates backend components
```

### New Files Created

1. **src/cmd/compile/selfhost/main.s**
   - Single entry point for bootstrap
   - Contains all import statements
   - SELFHOST_MAIN block for main() entry point
   - Seed compiler traces these imports to discover all packages

2. **src/cmd/compile/*/selfhost/{component}.s**
   - Aggregate packages for frontend, middlend, backend
   - Import all their respective subcomponents
   - Seed compiler recursively discovers transitive dependencies

3. **src/cmd/dist/native-bootstrap-no-manifest.sh**
   - New bootstrap script without manifest file
   - Supports 3-stage bootstrap with convergence verification
   - Provides detailed logging and diagnostics

## Build Commands

### Current (Manifest-based)
```bash
make native-bootstrap          # Use old approach
```

### New (Import-driven) - Experimental
```bash
make native-bootstrap-imports  # Use new approach
```

### Validation & Testing
```bash
make validate-imports          # Check all import statements
make test-bootstrap-both       # Compare both methods
```

## Migration Timeline

### Phase 1: Parallel Support (NOW)
- ✓ New import-driven infrastructure created
- ✓ Old manifest-based approach still works
- Both methods available for testing

### Phase 2: Validation (When ready)
- Run `make test-bootstrap-both`
- Compare binaries from both methods
- Verify convergence in both approaches
- Run full test suite with both

### Phase 3: Cutover (After validation)
- Switch default to `make native-bootstrap-imports`
- Keep old approach as fallback (SEED_USE_MANIFEST=1)
- Deprecation period with warnings

### Phase 4: Cleanup (After stabilization)
- Remove manifest file: `src/cmd/compile/selfhost-sources.txt`
- Remove old script: `src/cmd/dist/materialize-selfhost-source.sh`
- Remove old bootstrap script branches

## How Import Discovery Works

### Stage 1: Seed Compiler Compilation

```
$ s_seed --compile-unit stage1.ir src/cmd/compile/selfhost/main.s
```

The seed compiler:
1. Reads main.s
2. Sees `import "cmd.compile.frontend.selfhost"`
3. Searches for `src/cmd/compile/frontend/selfhost.s` or `selfhost/` directory
4. Recursively follows imports in discovered files
5. Collects all source files transitively
6. Compiles complete compilation unit

### Stage 2 & 3: Self-compilation

The generated stage1 compiler repeats the process on itself:
```
$ stage1 --compile-unit stage2.ir src/cmd/compile/selfhost/main.s
```

This ensures:
- Compiler can compile itself
- Binary converges (stage2 == stage3)
- Bootstrap chain is valid

## Debugging

### Check Imports
```bash
grep "^import" src/cmd/compile/selfhost/*.s
```

### Verbose Bootstrap
```bash
# Check logs from failed bootstrap
cat .bootstrap/native-imports/stage1-compile.log
cat .bootstrap/native-imports/stage1-emit.log
```

### Manual Stage Compilation
```bash
# Run only stage 1
bin/s_seed \
  --compile-unit .bootstrap/test.ir \
  src/cmd/compile/selfhost/main.s

# Emit binary
bin/s_seed \
  --emit-bin .bootstrap/test.ir \
  .bootstrap/stage1-test
```

## Comparison with Go

Go compiler uses a similar approach:

```go
// cmd/compile/main.go
package main

import (
    "cmd/compile/internal/ir"      // Frontend
    "cmd/compile/internal/syntax"   // Parser
    "cmd/compile/internal/ssa"      // IR
    // ... more packages
)

func main() {
    // Compiler entry point
}
```

The `go build` tool automatically traces these imports and compiles all necessary packages. This is exactly what we're implementing in S.

## Benefits Summary

| Aspect | Manifest | Import-driven |
|--------|----------|---------------|
| **Maintainability** | Manual, error-prone | Automatic, enforced |
| **Discoverability** | External file | In code (IDE-aware) |
| **Scalability** | Limited | Excellent |
| **Platform-specific** | Manual duplication | Via build tags |
| **IDE Support** | None | Full (imports) |
| **Industry standard** | Rare | Common (Go, Rust) |
| **Bootstrap reliability** | Lower | Higher |

## References

- Go Compiler Bootstrap: https://golang.org/doc/install/source
- LLVM Bootstrap Model: https://llvm.org/docs/GettingStarted/
- Rust Bootstrap: https://github.com/rust-lang/rust/tree/master/src/bootstrap

## Testing Checklist

Before fully migrating to import-driven bootstrap:

- [ ] `make validate-imports` passes
- [ ] `make native-bootstrap-imports` succeeds
- [ ] `make test-bootstrap-both` shows identical binaries
- [ ] Full test suite passes with imported compiler
- [ ] Regression tests pass
- [ ] Performance benchmarks unchanged
- [ ] Documentation updated
