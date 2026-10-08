# S Compiler Source File Organization

## Current Root Directory Files

Total: **14 .s files** in `/home/shuwen/shuwen/s/src/cmd/compile/`

### File Statistics

```
artifact.s                  1.6K   → pipeline.* 
asm_generation_examples.s   3.5K   → examples/demo
bootstrap_pure_s.s          4.2K   → bootstrap/
compiler_main.s             9.6K   → internal/compiler/
context.s                   165B   → internal/pipeline/
diagnostics.s               85B    → internal/pipeline/ (or delete)
elf_gen.s                   2.4K   → backend/codegen/
ir_codegen.s                4.8K   → middlend/ir/
ir_parser.s                 3.3K   → middlend/ir/
ir_to_binary.s              2.6K   → bootstrap/
main.s                      17K    → KEEP (entry point)
pipeline.s                  71B    → internal/pipeline/
stage.s                     201B   → internal/pipeline/
x86_64_codegen.s            5.6K   → backend/target/amd64/
═══════════════════════════════════════════════════
TOTAL (excluding main.s):   ~45KB   (could be reorganized)
```

---

## Recommended Organization

### Files by Category

#### 1. **KEEP IN ROOT** (1 file)
- **main.s** - Compiler entry point
  - Size: 17KB
  - Package: cmd
  - Reason: Primary entry point for bootstrap and regular compilation
  - Contains all selfhost imports

#### 2. **MOVE TO bootstrap/** (3 files)
```
bootstrap/
├── bootstrap_pure_s.s    (pure S bootstrap compiler)
├── ir_to_binary.s        (IR to executable converter)
└── .complete             (bootstrap completion marker)
```

**Rationale:** These are bootstrap-specific implementation files

#### 3. **MOVE TO internal/pipeline/** (4 files)
```
internal/pipeline/
├── artifact.s            (pipeline invariants and artifacts)
├── context.s             (pipeline context)
├── diagnostics.s         (diagnostics handling)
├── pipeline.s            (pipeline orchestration)
└── stage.s               (pipeline stages)
```

**Rationale:** All pipeline-related internal implementation

#### 4. **MOVE TO middlend/ir/** (2 files)
```
middlend/ir/
├── ir_codegen.s          (IR code generation)
├── ir_parser.s           (IR parsing)
└── ir.s                  (already exists?)
```

**Rationale:** Intermediate Representation handling is middlend responsibility

#### 5. **MOVE TO internal/compiler/** (1 file)
```
internal/compiler/
├── compiler_main.s       (compiler main logic)
└── compiler.s            (already exists?)
```

**Rationale:** Internal compiler implementation

#### 6. **MOVE TO backend/codegen/ or backend/target/amd64/** (2 files)
```
backend/codegen/
├── elf_gen.s             (ELF generation - architecture-neutral)

backend/target/amd64/
├── x86_64_codegen.s      (x86_64 specific code generation)
```

**Rationale:** Code generation is backend responsibility

#### 7. **MOVE TO misc/ or testing/examples/** (1 file)
```
misc/examples/
├── asm_generation_examples.s   (example assembly generation)

testing/examples/
├── asm_generation_examples.s   (demo/example code)
```

**Rationale:** Example code, not core compiler

---

## Migration Plan

### Phase 1: Low-Risk Moves (Independent Files)
✅ **Can move immediately** (no other files depend on them):

1. `bootstrap_pure_s.s` → `bootstrap/`
2. `ir_to_binary.s` → `bootstrap/`
3. `asm_generation_examples.s` → `misc/examples/` or `testing/examples/`

```bash
mkdir -p bootstrap
mkdir -p misc/examples

mv bootstrap_pure_s.s bootstrap/
mv ir_to_binary.s bootstrap/
mv asm_generation_examples.s misc/examples/
```

### Phase 2: Structural Moves (Update Imports)
⚠️ **Requires updating import statements**:

1. `ir_codegen.s`, `ir_parser.s` → `middlend/ir/`
2. `pipeline.s`, `stage.s`, `artifact.s`, `context.s`, `diagnostics.s` → `internal/pipeline/`
3. `compiler_main.s` → `internal/compiler/`
4. `elf_gen.s` → `backend/codegen/`
5. `x86_64_codegen.s` → `backend/target/amd64/`

Steps:
```bash
# Create directories if needed
mkdir -p middlend/ir
mkdir -p internal/pipeline
mkdir -p internal/compiler
mkdir -p backend/codegen
mkdir -p backend/target/amd64

# Move files
mv ir_codegen.s middlend/ir/
mv ir_parser.s middlend/ir/
mv pipeline.s internal/pipeline/
mv stage.s internal/pipeline/
mv artifact.s internal/pipeline/
mv context.s internal/pipeline/
mv diagnostics.s internal/pipeline/
mv compiler_main.s internal/compiler/
mv elf_gen.s backend/codegen/
mv x86_64_codegen.s backend/target/amd64/

# Then update imports in main.s and other files
```

### Phase 3: Verification
- [ ] Run `make validate-imports`
- [ ] Run `make clean`
- [ ] Run `make native-bootstrap-imports`
- [ ] Run full test suite

### Phase 4: Update Documentation
- [ ] Update this file with final structure
- [ ] Update README with new paths
- [ ] Document any breaking changes

---

## File-by-File Analysis

### 1. artifact.s (1.6KB)
```
Package: compile.pipeline
Purpose: Canonical pipeline invariant definitions
Move to: internal/pipeline/artifact.s
Risk: Low - internal pipeline file
Notes: Document what "canonical pipeline invariant" means
```

### 2. asm_generation_examples.s (3.5KB)
```
Package: demo
Purpose: Example assembly generation
Move to: misc/examples/asm_generation.s or testing/examples/
Risk: Low - standalone example
Notes: May want to rename for clarity
```

### 3. bootstrap_pure_s.s (4.2KB)
```
Package: main
Purpose: Pure S language bootstrap compiler implementation
Move to: bootstrap/bootstrap_pure.s
Risk: Very Low - self-contained bootstrap code
Notes: This is the core self-hosting mechanism
```

### 4. compiler_main.s (9.6KB)
```
Package: compile.compiler
Purpose: Main compiler driver logic
Move to: internal/compiler/main.s
Risk: Medium - likely imported by other files
Notes: Update any imports after move
```

### 5. context.s (165B)
```
Package: compile.pipeline
Purpose: Pipeline context definitions
Move to: internal/pipeline/context.s
Risk: Low - tiny file, likely standalone
Notes: Could merge into pipeline.s if very small
```

### 6. diagnostics.s (85B)
```
Package: compile.pipeline
Purpose: Diagnostic/error handling
Move to: internal/pipeline/diagnostics.s
Risk: Low - but verify no external dependencies
Notes: Very small file - consider consolidation
```

### 7. elf_gen.s (2.4KB)
```
Package: cmd
Purpose: ELF executable generation
Move to: backend/codegen/elf_gen.s
Risk: Medium - core backend functionality
Notes: ELF generation is architecture-neutral
```

### 8. ir_codegen.s (4.8KB)
```
Package: cmd
Purpose: IR to code generation
Move to: middlend/ir/codegen.s or backend/codegen/ir_codegen.s
Risk: Medium - central to compilation pipeline
Notes: Decide: part of IR analysis or backend?
```

### 9. ir_parser.s (3.3KB)
```
Package: ir
Purpose: Intermediate Representation parsing
Move to: middlend/ir/parser.s
Risk: Medium - part of IR subsystem
Notes: Should be with other IR files
```

### 10. ir_to_binary.s (2.6KB)
```
Package: main
Purpose: Convert IR to executable binary
Move to: bootstrap/ir_to_binary.s
Risk: Low - bootstrap utility
Notes: Part of self-hosting process
```

### 11. main.s (17KB)
```
Package: cmd
Purpose: Compiler entry point
Location: KEEP IN ROOT
Reason: Primary compilation entry point
Notes: Must stay where it is
```

### 12. pipeline.s (71B)
```
Package: compile.pipeline
Purpose: Pipeline orchestration
Move to: internal/pipeline/pipeline.s
Risk: Low - internal pipeline file
Notes: Very small file
```

### 13. stage.s (201B)
```
Package: compile.pipeline
Purpose: Compilation stages definition
Move to: internal/pipeline/stage.s
Risk: Low - internal pipeline file
Notes: Very small file - consider consolidation
```

### 14. x86_64_codegen.s (5.6KB)
```
Package: cmd
Purpose: x86_64 architecture code generation
Move to: backend/target/amd64/codegen.s
Risk: Medium - architecture-specific
Notes: Part of target-specific backend
       Should go in target subdirectory structure
```

---

## Benefits of Reorganization

### Before (Current)
```
src/cmd/compile/
├── main.s (17KB - entry point)
├── bootstrap_pure_s.s (4.2KB - bootstrap code mixed with core)
├── ir_codegen.s, ir_parser.s (middlend in root)
├── pipeline.s, stage.s, artifact.s (internal in root)
├── compiler_main.s (internal in root)
├── elf_gen.s (backend code in root)
├── x86_64_codegen.s (target-specific in root)
└── [14 files total in root]
```

**Issues:**
- ❌ Root directory cluttered
- ❌ No clear separation of concerns
- ❌ IDE navigation difficult
- ❌ New developers confused about file locations
- ❌ Inconsistent with package names

### After (Proposed)
```
src/cmd/compile/
├── main.s (17KB - ONLY entry point in root)
├── bootstrap/
│   ├── bootstrap_pure.s
│   └── ir_to_binary.s
├── internal/pipeline/
│   ├── pipeline.s
│   ├── stage.s
│   ├── artifact.s
│   ├── context.s
│   └── diagnostics.s
├── middlend/ir/
│   ├── codegen.s
│   └── parser.s
├── internal/compiler/
│   └── main.s
├── backend/codegen/
│   └── elf_gen.s
├── backend/target/amd64/
│   └── codegen.s
└── misc/examples/
    └── asm_generation.s
```

**Benefits:**
- ✅ Clean root directory (only main.s)
- ✅ Clear separation of concerns
- ✅ Matches package structure
- ✅ IDE navigation improved
- ✅ Consistent with compiler architecture
- ✅ Easier for new developers

---

## Implementation Checklist

### Before Starting
- [ ] Review current usage of each file
- [ ] Check for cross-file dependencies
- [ ] Verify package declarations are correct
- [ ] Create backup/branch

### Phase 1: Low-Risk Moves
- [ ] Move `bootstrap_pure_s.s` → `bootstrap/`
- [ ] Move `ir_to_binary.s` → `bootstrap/`
- [ ] Move `asm_generation_examples.s` → `misc/examples/`
- [ ] Test with `make validate-imports`

### Phase 2: Medium-Risk Moves
- [ ] Move IR-related files → `middlend/ir/`
- [ ] Move pipeline files → `internal/pipeline/`
- [ ] Move compiler files → `internal/compiler/`
- [ ] Update imports in affected files
- [ ] Test with `make validate-imports`

### Phase 3: Backend Organization
- [ ] Move backend code → `backend/codegen/` or `backend/target/*/`
- [ ] Consider x86_64/ARM64 separation
- [ ] Update build configuration
- [ ] Test with bootstrap

### Verification
- [ ] Run all validation: `make validate-imports`
- [ ] Build with clean: `make clean && make native-bootstrap-imports`
- [ ] Run full test suite
- [ ] Cross-platform test (if possible)

---

## Recommendations

### Priority 1: MUST DO
1. Keep `main.s` in root (entry point)
2. Move bootstrap files (clear separation)
3. Move example files to examples/ directory

### Priority 2: SHOULD DO
1. Move internal pipeline files
2. Move IR files to middlend/
3. Move backend code to backend/

### Priority 3: NICE TO HAVE
1. Create target-specific subdirectories
2. Further consolidate small files
3. Rename files for consistency

### Priority 4: CONSIDER
1. Merge very small files (context.s, diagnostics.s, pipeline.s, stage.s)
2. Create `internal/` subdirectories systematically
3. Add README files to explain organization

---

## Estimated Work

- **Phase 1**: 15 minutes (3 files, low-risk)
- **Phase 2**: 30 minutes (7 files, update imports, test)
- **Phase 3**: 30 minutes (backend organization, testing)
- **Verification**: 30 minutes (full test suite)

**Total**: ~2 hours for complete reorganization

---

## Notes

- **Reversibility**: All changes are reversible (git revert if needed)
- **Testing**: Each phase has validation gates
- **Documentation**: Update after each phase
- **Breaking Changes**: None expected if done carefully
- **Performance**: No performance impact expected

---

## References

- Current directory: `src/cmd/compile/`
- Related: [CONSOLIDATION_SUMMARY.md](CONSOLIDATION_SUMMARY.md)
- Documentation: [BOOTSTRAP_MODERNIZATION.md](BOOTSTRAP_MODERNIZATION.md)

**Status**: Ready for reorganization planning
