#!/bin/sh
# Self-hosted compiler bootstrap without manifest file
# Uses automatic import resolution (Go-style)
#
# Architecture:
#   seed compiler → trace imports → resolve packages → compile complete system
#
# This script replaces the old materialize-selfhost-source.sh + manifest approach
# with a modern import-driven bootstrap model.

set -eu

root=${S_SOURCE_ROOT:-$(pwd)}
output_dir=${1:?usage: native-bootstrap-no-manifest.sh OUTPUT_DIR}
mkdir -p "$output_dir"

# Export environment for seed compiler
export S_COMPILER_SOURCES="$root/src/cmd/compile"
export S_TARGET_OS=${S_TARGET_OS:-$(uname -s | tr '[:upper:]' '[:lower:]')}
export S_TARGET_ARCH=${S_TARGET_ARCH:-$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')}

# Verify seed compiler exists
[ -x "$root/bin/s_seed" ] || {
    printf 'Error: seed compiler not found at %s/bin/s_seed\n' "$root" >&2
    exit 1
}

# Verify main entry point exists
[ -f "$root/src/cmd/compile/main.s" ] || {
    printf 'Error: main entry point not found\n' >&2
    exit 1
}

echo "=== S Compiler Bootstrap (Import-Driven Model) ==="
echo "Source Root: $root"
echo "Output Dir:  $output_dir"
echo "Target:      $S_TARGET_OS/$S_TARGET_ARCH"
echo ""

# Stage 1: Compile with seed compiler
# Seed compiler automatically traces imports and resolves packages
echo "=== Stage 1: Bootstrap with Seed Compiler ==="
printf "Compiling self-hosted compiler entry point...\n"

"$root/bin/s_seed" \
    --compile-unit "$output_dir/stage1.ir" \
    "$root/src/cmd/compile/main.s" \
    2>&1 | tee "$output_dir/stage1-compile.log" || {
    printf "Error: Stage 1 compilation failed\n" >&2
    exit 1
}

echo "✓ Generated IR: $output_dir/stage1.ir"

# Emit binary for stage 1
printf "Generating stage 1 binary...\n"
"$root/bin/s_seed" \
    --emit-bin "$output_dir/stage1.ir" \
    "$output_dir/stage1" \
    2>&1 | tee "$output_dir/stage1-emit.log" || {
    printf "Error: Stage 1 binary generation failed\n" >&2
    exit 1
}

chmod +x "$output_dir/stage1"
echo "✓ Generated Binary: $output_dir/stage1"

# Stage 2: Compile with stage1 (self-compilation)
echo ""
echo "=== Stage 2: Self-Compilation with Stage 1 ==="
printf "Compiling with generated compiler...\n"

"$output_dir/stage1" \
    --compile-unit "$output_dir/stage2.ir" \
    "$root/src/cmd/compile/main.s" \
    2>&1 | tee "$output_dir/stage2-compile.log" || {
    printf "Error: Stage 2 compilation failed\n" >&2
    exit 1
}

echo "✓ Generated IR: $output_dir/stage2.ir"

# Emit binary for stage 2
printf "Generating stage 2 binary...\n"
"$output_dir/stage1" \
    --emit-bin "$output_dir/stage2.ir" \
    "$output_dir/stage2" \
    2>&1 | tee "$output_dir/stage2-emit.log" || {
    printf "Error: Stage 2 binary generation failed\n" >&2
    exit 1
}

chmod +x "$output_dir/stage2"
echo "✓ Generated Binary: $output_dir/stage2"

# Stage 3: Verify convergence (triple verification)
echo ""
echo "=== Stage 3: Convergence Verification ==="
printf "Verifying bootstrap stability...\n"

"$output_dir/stage2" \
    --compile-unit "$output_dir/stage3.ir" \
    "$root/src/cmd/compile/main.s" \
    2>&1 | tee "$output_dir/stage3-compile.log" || {
    printf "Error: Stage 3 compilation failed\n" >&2
    exit 1
}

"$output_dir/stage2" \
    --emit-bin "$output_dir/stage3.ir" \
    "$output_dir/stage3" \
    2>&1 | tee "$output_dir/stage3-emit.log" || {
    printf "Error: Stage 3 binary generation failed\n" >&2
    exit 1
}

chmod +x "$output_dir/stage3"
echo "✓ Generated Binary: $output_dir/stage3"

# Convergence check: stage2 and stage3 should be identical
echo ""
echo "=== Bootstrap Convergence Check ==="
if cmp -s "$output_dir/stage2" "$output_dir/stage3"; then
    echo "✓ SUCCESS: Bootstrap converged (stage2 == stage3)"
    echo "✓ Bootstrap chain verified: seed → stage1 → stage2 ≡ stage3"
    
    # Mark bootstrap as complete
    touch "$output_dir/.complete"
    
    # Summary
    echo ""
    echo "=== Bootstrap Summary ==="
    ls -lh "$output_dir/stage"* | grep -v '\.log' | grep -v '\.ir'
    echo ""
    echo "Bootstrap artifacts ready in: $output_dir"
else
    # Binary comparison failed, check sizes
    size2=$(stat -f%z "$output_dir/stage2" 2>/dev/null || stat -c%s "$output_dir/stage2")
    size3=$(stat -f%z "$output_dir/stage3" 2>/dev/null || stat -c%s "$output_dir/stage3")
    
    printf "Error: Bootstrap did not converge\n" >&2
    printf "  stage2 size: %d bytes\n" "$size2" >&2
    printf "  stage3 size: %d bytes\n" "$size3" >&2
    exit 1
fi
