PREFIX ?= $(HOME)/.local
INSTALL_BIN_DIR ?= $(PREFIX)/bin
INSTALL_PROGRAM ?= install
SUDO ?=
VERBOSE ?= 1
.DEFAULT_GOAL := help
SELFHOST_DIR ?= $(CURDIR)/.bootstrap/selfhost
NATIVE_BOOTSTRAP_DIR := $(SELFHOST_DIR)/native
NATIVE_BOOTSTRAP_STAMP := $(NATIVE_BOOTSTRAP_DIR)/.complete
S_HOST_OS := $(shell uname -s | tr '[:upper:]' '[:lower:]')
S_HOST_ARCH := $(shell uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')
S_TARGET_OS ?= $(S_HOST_OS)
S_TARGET_ARCH ?= $(S_HOST_ARCH)
PARALLEL_JOBS ?= $(shell nproc 2>/dev/null || echo 4)

# ============================================================================
# Seed Compiler (trusted C bootstrap compiler)
# ============================================================================
SEED_COMPILER_SOURCES := $(wildcard src/cmd/compile/seed/*.c src/cmd/compile/seed/*/*.c src/cmd/compile/seed/*/*/*.c src/cmd/compile/seed/*/*/*/*.c src/cmd/compile/seed/*/*.h src/cmd/compile/seed/*/*/*.h)

seed-compiler-bin: bin/s_seed

bin/s_seed: $(SEED_COMPILER_SOURCES)
	@mkdir -p ./bin
	@echo "Building seed compiler..."
	@set -e; tmp="$$(mktemp ./bin/s_seed.XXXXXX)"; trap 'rm -f "$$tmp"' EXIT HUP INT TERM; \
	  gcc -std=c11 -Wall -Wextra -Werror \
	  -o "$$tmp" \
	  src/cmd/compile/seed/s_seed.c \
	  src/cmd/compile/seed/bootstrap/bootstrap.c \
	  src/cmd/compile/seed/lexical/lexer.c \
	  src/cmd/compile/seed/lexical/selfhost_bridge.c \
	  src/cmd/compile/seed/error/error.c \
	  src/cmd/compile/seed/syntax/parser.c \
	  src/cmd/compile/seed/semantic/analyzer.c \
	  src/cmd/compile/seed/intermediate/ir.c \
	  src/cmd/compile/seed/code/generator.c \
	  src/cmd/compile/seed/code/backend_registry.c \
	  src/cmd/compile/seed/code/native_backend.c \
	  src/cmd/compile/seed/code/standalone_amd64_backend.c \
	  src/cmd/compile/seed/runtime/network_windows.c \
	  src/cmd/compile/seed/runtime/runtime.c; \
	  mv "$$tmp" ./bin/s_seed; \
	  trap - EXIT HUP INT TERM

# ============================================================================
# Native Bootstrap (self-hosted compiler)
# DEPRECATED: Use 'make native-bootstrap-imports' for modern import-driven approach
# ============================================================================
NATIVE_BOOTSTRAP_INPUTS := \
  $(SEED_COMPILER_SOURCES) \
  src/cmd/compile/frontend/selfhost/source_scan.s \
  src/cmd/compile/middlend/selfhost/const_eval.s \
  src/cmd/compile/backend/selfhost/elf_slices.s \
  src/cmd/compile/backend/selfhost/asm_amd64.s \
  src/cmd/compile/backend/selfhost/asm_arm64.s \
  src/cmd/compile/main.s \
  src/cmd/compile/backend/selfhost/c_emit.s \
  src/cmd/dist/native-bootstrap.sh \
  src/runtime/selfhost_linux_amd64.S \
  src/runtime/linker/nostdlib.ld

native-bootstrap: seed-compiler-bin $(NATIVE_BOOTSTRAP_STAMP)
	@echo "⚠️  DEPRECATED: Use 'make native-bootstrap-imports' instead"
	@echo "    (This uses the old manifest-based approach)"

$(NATIVE_BOOTSTRAP_STAMP): $(NATIVE_BOOTSTRAP_INPUTS)
	@mkdir -p "$(NATIVE_BOOTSTRAP_DIR)"
	@S_SOURCE_ROOT=$(CURDIR) S_TARGET_OS=$(S_TARGET_OS) S_TARGET_ARCH=$(S_TARGET_ARCH) ./src/cmd/dist/native-bootstrap.sh \
	  "$(NATIVE_BOOTSTRAP_DIR)"
	@touch "$@"

.PHONY: native-bootstrap-diagnostic-check
native-bootstrap-diagnostic-check:
	@S_SOURCE_ROOT=$(CURDIR) ./test/native-bootstrap-diagnostic/check.sh

# ============================================================================
# Native Bootstrap (Import-Driven Model - No Manifest)
# ============================================================================
# New bootstrap approach: automatic import resolution (like Go compiler)
# Files resolve dependencies via import statements, no manifest needed

NATIVE_BOOTSTRAP_IMPORTS_INPUTS := \
  $(SEED_COMPILER_SOURCES) \
  src/cmd/compile/main.s \
  src/cmd/compile/frontend/selfhost/frontend.s \
  src/cmd/compile/middlend/selfhost/middlend.s \
  src/cmd/compile/backend/selfhost/backend.s \
  src/cmd/compile/frontend/selfhost/source_scan.s \
  src/cmd/compile/middlend/selfhost/const_eval.s \
  src/cmd/compile/backend/selfhost/elf_slices.s \
  src/cmd/compile/backend/selfhost/asm_amd64.s \
  src/cmd/compile/backend/selfhost/asm_arm64.s \
  src/cmd/compile/backend/selfhost/c_emit.s \
  src/cmd/dist/native-bootstrap-no-manifest.sh

.PHONY: native-bootstrap-imports
native-bootstrap-imports: seed-compiler-bin
	@mkdir -p .bootstrap/native-imports
	@S_SOURCE_ROOT=$(CURDIR) S_TARGET_OS=$(S_TARGET_OS) S_TARGET_ARCH=$(S_TARGET_ARCH) \
	  ./src/cmd/dist/native-bootstrap-no-manifest.sh .bootstrap/native-imports
	@echo "✓ Import-driven bootstrap complete (.bootstrap/native-imports)"

.PHONY: validate-imports
validate-imports:
	@echo "Validating import statements for bootstrap..."
	@if grep -q "cmd.compile.frontend.selfhost" src/cmd/compile/main.s; then \
	  echo "  ✓ main.s imports frontend.selfhost"; \
	else \
	  echo "  ✗ main.s missing frontend.selfhost import"; exit 1; \
	fi
	@if grep -q "cmd.compile.middlend.selfhost" src/cmd/compile/main.s; then \
	  echo "  ✓ main.s imports middlend.selfhost"; \
	else \
	  echo "  ✗ main.s missing middlend.selfhost import"; exit 1; \
	fi
	@if grep -q "cmd.compile.backend.selfhost" src/cmd/compile/main.s; then \
	  echo "  ✓ main.s imports backend.selfhost"; \
	else \
	  echo "  ✗ main.s missing backend.selfhost import"; exit 1; \
	fi
	@if grep -q "^import" src/cmd/compile/frontend/selfhost/frontend.s; then \
	  echo "  ✓ frontend.s has imports"; \
	else \
	  echo "  ✗ frontend.s missing imports"; exit 1; \
	fi
	@if grep -q "^import" src/cmd/compile/middlend/selfhost/middlend.s; then \
	  echo "  ✓ middlend.s has imports"; \
	else \
	  echo "  ✗ middlend.s missing imports"; exit 1; \
	fi
	@if grep -q "^import" src/cmd/compile/backend/selfhost/backend.s; then \
	  echo "  ✓ backend.s has imports"; \
	else \
	  echo "  ✗ backend.s missing imports"; exit 1; \
	fi
	@echo "✓ All bootstrap imports validated"

.PHONY: test-bootstrap-both
test-bootstrap-both: clean
	@echo "=== Testing Both Bootstrap Methods ==="
	@echo ""
	@echo "1. Original (manifest-based):"
	@make native-bootstrap || echo "  [FAILED]"
	@echo ""
	@echo "2. New (import-driven):"
	@make native-bootstrap-imports || echo "  [FAILED]"
	@echo ""
	@echo "=== Comparison ==="
	@echo "Manifest-based:  .bootstrap/selfhost/native/stage2"
	@echo "Import-driven:   .bootstrap/native-imports/stage2"
	@if [ -f .bootstrap/selfhost/native/stage2 ] && [ -f .bootstrap/native-imports/stage2 ]; then \
	  if cmp -s .bootstrap/selfhost/native/stage2 .bootstrap/native-imports/stage2; then \
	    echo "✓ Both methods produce identical binaries!"; \
	  else \
	    echo "✗ Binaries differ (investigation needed)"; \
	  fi \
	else \
	  echo "✗ One or both bootstrap methods failed"; \
	fi


# ============================================================================
# Compiler (no-GC S compiler in S language)
# ============================================================================
COMPILER_SOURCES := \
	src/cmd/compile/frontend/core.s \
	src/cmd/compile/frontend/frontend.s \
	src/cmd/compile/frontend/stages.s \
	src/cmd/compile/middlend/mir/compiler_emit.s \
	src/cmd/compile/middlend/stages.s \
	src/cmd/compile/compiler_main.s

compiler: seed-compiler-bin
	@mkdir -p .bootstrap/compiler bin
	@./bin/s_seed --compile-unit .bootstrap/compiler/compiler.ir $(COMPILER_SOURCES)
	@S_SOURCE_ROOT=$(CURDIR) S_TARGET_OS=$$(uname -s | tr '[:upper:]' '[:lower:]') \
	  S_TARGET_ARCH=$$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/') \
	  ./bin/s_seed --emit-bin .bootstrap/compiler/compiler.ir ./bin/s_compiler
	@cp misc/scripts/s-driver.sh ./bin/s
	@chmod +x ./bin/s

# ============================================================================
# Installation
# ============================================================================
.PHONY: install
install: compiler
	@mkdir -p "$(INSTALL_BIN_DIR)"
	@$(INSTALL_PROGRAM) -m 0755 ./bin/s_compiler "$(INSTALL_BIN_DIR)/s"
	@echo "Installed S compiler to: $(INSTALL_BIN_DIR)/s"
	@echo "Usage: $(INSTALL_BIN_DIR)/s <file.s>"

# ============================================================================
# Self-hosted compiler
# ============================================================================
selfhost: native-bootstrap
	@$(INSTALL_PROGRAM) -m 0755 $(SELFHOST_DIR)/native/stage2 ./bin/s
	@echo "Installed S self-hosted compiler: ./bin/s"
	@echo "Verified bootstrap chain: seed -> stage1 -> stage2 -> stage3"

# ============================================================================
# Pipeline
# ============================================================================
.PHONY: pipeline
pipeline: compiler
	@chmod +x scripts/compile-pipeline-check.sh
	@S_SOURCE_ROOT=$(CURDIR) scripts/compile-pipeline-check.sh

# ============================================================================
# Cleanup
# ============================================================================
.PHONY: clean
clean:
	@echo "Cleaning all generated files..."
	@rm -rf .bootstrap/oom-* \
	        .bootstrap/full-native-bootstrap-* \
	        .bootstrap/memory-investigation \
	        .bootstrap/split-check \
	        .bootstrap/stage[0-9] \
	        .bootstrap/stage[0-9][0-9] \
	        .bootstrap/stage*-* \
	        .bootstrap/stage2-stage3-diagnostic \
	        .bootstrap/compiler \
	        .bootstrap/native \
	        .bootstrap/selfhost \
	        bin/s_seed bin/s_compiler bin/s
	@echo "✓ Cleaned: all build artifacts and generated files"

.PHONY: help
help:
	@echo "  make pipeline"
	@echo "  make install"
	@echo "  make selfhost"
	@echo "  make clean"
	@echo ""
	@echo "  make native-bootstrap-imports - Bootstrap with import-driven model (experimental)"
	@echo "  make validate-imports          - Validate import statements"
	@echo "  make test-bootstrap-both       - Test both bootstrap methods"
