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

# S-written stage controller. This target builds the controller only; the
# complete compiler bootstrap is a separate execution with a fresh output dir.
.PHONY: s-dist-bootstrap-bin
s-dist-bootstrap-bin: seed-compiler-bin
	@mkdir -p .bootstrap/s-dist
	./bin/s_seed src/cmd/dist/bootstrap.s .bootstrap/s-dist/bootstrap.ir
	./bin/s_seed --emit-bin .bootstrap/s-dist/bootstrap.ir .bootstrap/s-dist/s-dist-bootstrap

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
  src/cmd/compile/internal/selfhost/source_scan.s \
  src/cmd/compile/internal/selfhost/const_eval.s \
  src/cmd/compile/internal/selfhost/elf_slices.s \
  src/cmd/compile/internal/selfhost/asm_amd64.s \
  src/cmd/compile/internal/selfhost/asm_arm64.s \
  src/cmd/compile/main.s \
  src/cmd/compile/internal/selfhost/c_emit.s \
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
  src/cmd/compile/internal/selfhost/frontend.s \
  src/cmd/compile/internal/selfhost/middlend.s \
  src/cmd/compile/internal/selfhost/backend.s \
  src/cmd/compile/internal/selfhost/source_scan.s \
  src/cmd/compile/internal/selfhost/const_eval.s \
  src/cmd/compile/internal/selfhost/elf_slices.s \
  src/cmd/compile/internal/selfhost/asm_amd64.s \
  src/cmd/compile/internal/selfhost/asm_arm64.s \
  src/cmd/compile/internal/selfhost/c_emit.s \
  src/cmd/dist/native-bootstrap-no-manifest.sh

.PHONY: native-bootstrap-imports
native-bootstrap-imports: seed-compiler-bin
	@mkdir -p .bootstrap/native-imports
	@S_SOURCE_ROOT=$(CURDIR) S_TARGET_OS=$(S_TARGET_OS) S_TARGET_ARCH=$(S_TARGET_ARCH) \
	  ./src/cmd/dist/native-bootstrap-no-manifest.sh .bootstrap/native-imports
	@echo "✓ Import-driven bootstrap complete (.bootstrap/native-imports)"

# ============================================================================
# Hosted Bootstrap (Go-style multi-stage approach)
# ============================================================================
# Workaround for IR backend's lack of generic monomorphization support.
# Uses hosted compiler to build intermediate stages, similar to Go 1.5+.
# 
# Stages:
#   Stage 0: Seed compiler (C) -> stage1.ir (using native-bootstrap-imports)
#   Stage 1: Hosted compiler -> stage1_bin (using --emit-c)
#   Stage 2: stage1_bin -> stage2.ir (self-host)
#   Stage 3: Verification
#
# This approach works around the architectural limitation that the native
# IR backend cannot generate code for generic methods. Once generic 
# monomorphization is implemented, this can transition to pure native bootstrap.

.PHONY: hosted-bootstrap
hosted-bootstrap: native-bootstrap-imports
	@echo "Building hosted bootstrap..."
	@mkdir -p .bootstrap/hosted
	@S_SOURCE_ROOT=$(CURDIR) S_TARGET_OS=$(S_TARGET_OS) S_TARGET_ARCH=$(S_TARGET_ARCH) \
	  ./src/cmd/dist/hosted-bootstrap.sh .bootstrap/hosted
	@echo "✓ Hosted bootstrap complete (.bootstrap/hosted)"

.PHONY: selfhost-protocol-check
selfhost-protocol-check: seed-compiler-bin
	@bash test/native-bootstrap-diagnostic/hosted_program_check.sh
	@bash test/native-bootstrap-diagnostic/native_artifact_check.sh
	@bash test/native-bootstrap-diagnostic/native_package_scope_check.sh
	@bash test/native-bootstrap-diagnostic/native_bootstrap_gate_check.sh
	@bash test/native-bootstrap-diagnostic/standalone_reachability_check.sh
	@bash test/native-bootstrap-diagnostic/native_source_reader_check.sh
	@bash test/native-bootstrap-diagnostic/native_host_tools_check.sh
	@bash test/native-bootstrap-diagnostic/native_global_state_check.sh
	@bash test/native-bootstrap-diagnostic/native_fs_result_check.sh
	@bash test/native-bootstrap-diagnostic/native_string_index_check.sh
	@bash test/native-bootstrap-diagnostic/native_contains_text_check.sh
	@bash test/native-bootstrap-diagnostic/native_stdout_bridge_check.sh

.PHONY: selfhost-native-stage1-check
selfhost-native-stage1-check: seed-compiler-bin
	@bash test/native-bootstrap-diagnostic/native_stage1_check.sh

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
	@if grep -q "^import" src/cmd/compile/internal/selfhost/frontend.s; then \
	  echo "  ✓ frontend.s has imports"; \
	else \
	  echo "  ✗ frontend.s missing imports"; exit 1; \
	fi
	@if grep -q "^import" src/cmd/compile/internal/selfhost/middlend.s; then \
	  echo "  ✓ middlend.s has imports"; \
	else \
	  echo "  ✗ middlend.s missing imports"; exit 1; \
	fi
	@if grep -q "^import" src/cmd/compile/internal/selfhost/backend.s; then \
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
	src/cmd/compile/main.s \
	src/cmd/compile/internal/driver/driver.s \
	src/cmd/compile/internal/pipeline/authority.s \
	src/cmd/compile/internal/pipeline/pipeline.s \
	src/cmd/compile/internal/compiler/frontend_core.s \
	src/cmd/compile/internal/compiler/frontend.s \
	src/cmd/compile/internal/compiler/native_frontend.s \
	src/cmd/compile/internal/mir/program.s \
	src/cmd/compile/internal/mir/program_enum.s \
	src/cmd/compile/internal/ir/program_lower.s \
	src/cmd/compile/internal/ir/program_enum.s \
	src/cmd/compile/internal/compiler/canonical_source.s \
	src/cmd/compile/internal/ssa/program.s \
	src/cmd/compile/internal/ssa/function_lower.s \
	src/cmd/compile/internal/codegen/amd64_program.s \
	src/cmd/compile/internal/core/native_build.s \
	src/cmd/compile/internal/compiler/frontend_stages.s \
	src/cmd/compile/internal/mir/compiler_emit.s \
	src/cmd/compile/internal/compiler/stages.s \
	src/cmd/compile/internal/compiler/main.s \
	src/cmd/compile/internal/compiler/compiler.s \
	src/cmd/compile/internal/compiler/bridge.s \
	src/cmd/compile/internal/rewriteresults/rewriteresults.s \
	src/cmd/compile/internal/slice/slice.s \
	src/cmd/compile/internal/walk/assign.s \
	src/cmd/compile/internal/walk/builtin.s \
	src/cmd/compile/internal/walk/closure.s \
	src/cmd/compile/internal/walk/compare.s \
	src/cmd/compile/internal/walk/complit.s \
	src/cmd/compile/internal/walk/convert.s \
	src/cmd/compile/internal/walk/expr.s \
	src/cmd/compile/internal/walk/order.s \
	src/cmd/compile/internal/walk/range.s \
	src/cmd/compile/internal/walk/select.s \
	src/cmd/compile/internal/walk/stmt.s \
	src/cmd/compile/internal/walk/switch.s \
	src/cmd/compile/internal/walk/temp.s \
	src/cmd/compile/internal/walk/walk.s \
	src/cmd/compile/internal/ssagen/arch.s \
	src/cmd/compile/internal/ssagen/abi.s \
	src/cmd/compile/internal/ssagen/intrinsics.s \
	src/cmd/compile/internal/ssagen/nowb.s \
	src/cmd/compile/internal/ssagen/pgen.s \
	src/cmd/compile/internal/ssagen/phi.s \
	src/cmd/compile/internal/ssagen/simdintrinsics.s \
	src/cmd/compile/internal/ssagen/ssa.s \
	src/cmd/compile/internal/ssa/op.s \
	src/cmd/compile/internal/ssa/value.s \
	src/cmd/compile/internal/ssa/block.s \
	src/cmd/compile/internal/ssa/func.s \
	src/cmd/compile/internal/ssa/config.s \
	src/cmd/compile/internal/ssa/cache.s \
	src/cmd/compile/internal/ssa/uses.s \
	src/cmd/compile/internal/ssa/rewrite.s \
	src/cmd/compile/internal/ssa/rewritegeneric.s \
	src/cmd/compile/internal/ssa/rewriteAMD64.s \
	src/cmd/compile/internal/ssa/rewriteARM64.s \
	src/cmd/compile/internal/ssa/rewriteARM.s \
	src/cmd/compile/internal/ssa/deadcode.s \
	src/cmd/compile/internal/ssa/cse.s \
	src/cmd/compile/internal/ssa/copyelim.s \
	src/cmd/compile/internal/ssa/dom.s \
	src/cmd/compile/internal/ssa/prove.s \
	src/cmd/compile/internal/ssa/regalloc.s \
	src/cmd/compile/internal/ssa/schedule.s \
	src/cmd/compile/internal/ssa/stackalloc.s \
	src/cmd/compile/internal/ssa/check.s \
	src/cmd/compile/internal/ssa/print.s \
	src/cmd/compile/internal/ssa/compile.s

# P1 canonical AST authority slice. Resolve its imported S parser and semantic
# consumer from the source graph so the production artifact carries one AST.
COMPILER_SOURCES += $(shell mkdir -p .bootstrap/compiler; canonical_closure=$$(mktemp .bootstrap/compiler/p1-canonical-closure.XXXXXX) || exit 1; trap 'rm -f "$$canonical_closure"' EXIT; ./src/cmd/dist/source_closure.sh src/cmd/compile/internal/canonical/canonical_ast_check.s "$$canonical_closure" >/dev/null && cat "$$canonical_closure")

.PHONY: compiler-source-list
compiler-source-list:
	@printf '%s\n' $(COMPILER_SOURCES)

compiler: seed-compiler-bin
	@mkdir -p .bootstrap/compiler bin
	@echo "compiler-entry=$(CURDIR)/src/cmd/compile/main.s"
	@for src in $(COMPILER_SOURCES); do echo "compiler-source=$$src"; done
	@./bin/s_seed --compile-native-unit .bootstrap/compiler/compiler.ir $(COMPILER_SOURCES)
	@S_SOURCE_ROOT=$(CURDIR) S_TARGET_OS=$$(uname -s | tr '[:upper:]' '[:lower:]') \
	  S_TARGET_ARCH=$$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/') \
	  ./bin/s_seed --emit-standalone-amd64 .bootstrap/compiler/compiler.ir ./bin/s_compiler
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
selfhost: native-bootstrap-imports
	@$(INSTALL_PROGRAM) -m 0755 .bootstrap/native-imports/stage3 ./bin/s
	@echo "Installed S self-hosted compiler: ./bin/s"
	@echo "Verified bootstrap chain: seed -> stage1 -> stage2 -> stage3"

# ============================================================================
# Pipeline
# ============================================================================
.PHONY: pipeline
pipeline: compiler
	@chmod +x script/compile-pipeline-check.sh
	@S_SOURCE_ROOT=$(CURDIR) script/compile-pipeline-check.sh

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

.PHONY: selfhost-native-record-check
selfhost-native-record-check: seed-compiler-bin
	@bash test/native-bootstrap-diagnostic/native_semantic_closure_check.sh
	@bash test/native-bootstrap-diagnostic/native_stage5_ast_check.sh
	@bash test/native-bootstrap-diagnostic/native_ast_param_type_check.sh
	@bash test/native-bootstrap-diagnostic/native_const_option_check.sh
	@bash test/native-bootstrap-diagnostic/native_generic_pattern_ref_check.sh
	@bash test/native-bootstrap-diagnostic/native_declaration_kind_check.sh
	@bash test/native-bootstrap-diagnostic/native_mono_literal_type_check.sh
	@bash test/native-bootstrap-diagnostic/native_mono_body_option_check.sh
	@bash test/native-bootstrap-diagnostic/native_lower_entry_check.sh
	@bash test/native-bootstrap-diagnostic/native_call_option_context_check.sh
	@bash test/native-bootstrap-diagnostic/native_explicit_option_check.sh
	@bash test/native-bootstrap-diagnostic/native_ir_stmt_constructor_check.sh
	@bash test/native-bootstrap-diagnostic/native_schedule_id_check.sh
	@bash test/native-bootstrap-diagnostic/native_empty_mir_graph_check.sh
	@bash test/native-bootstrap-diagnostic/native_mir_box_projection_check.sh
	@bash test/native-bootstrap-diagnostic/native_borrow_report_check.sh
	@bash test/native-bootstrap-diagnostic/native_buildcfg_contract_check.sh
	@bash test/native-bootstrap-diagnostic/native_escape_sites_check.sh
	@bash test/native-bootstrap-diagnostic/native_vec_set_check.sh
	@bash test/native-bootstrap-diagnostic/native_bool_payload_check.sh
	@bash test/native-bootstrap-diagnostic/native_hex_integer_check.sh
	@bash test/native-bootstrap-diagnostic/native_qualified_array_literal_check.sh
	@bash test/native-bootstrap-diagnostic/native_recursive_enum_check.sh
	@bash test/native-bootstrap-diagnostic/native_tuple_return_check.sh
	@bash test/native-bootstrap-diagnostic/native_tuple_expression_check.sh
	@bash test/native-bootstrap-diagnostic/native_canonical_type_tree_check.sh
	@bash test/native-bootstrap-diagnostic/native_canonical_type_schema_check.sh
	@bash test/native-bootstrap-diagnostic/native_extern_result_return_check.sh
	@bash test/native-bootstrap-diagnostic/native_alias_return_identity_check.sh
	@bash test/native-bootstrap-diagnostic/native_mono_type_args_check.sh
	@bash test/native-bootstrap-diagnostic/native_pattern_payload_identity_check.sh
	@bash test/native-bootstrap-diagnostic/native_backend_bool_boundary_check.sh
	@bash test/native-bootstrap-diagnostic/native_enum_identity_check.sh
	@bash test/native-bootstrap-diagnostic/native_array_record_identity_check.sh
	@bash test/native-bootstrap-diagnostic/native_generic_caller_borrow_check.sh
	@bash test/native-bootstrap-diagnostic/native_generic_record_check.sh
	@bash test/native-bootstrap-diagnostic/native_generic_enum_check.sh
	@bash test/native-bootstrap-diagnostic/native_option_payload_check.sh
	@bash test/native-bootstrap-diagnostic/native_unit_check.sh
	@bash test/native-bootstrap-diagnostic/native_record_parameter_order_check.sh
	@bash test/native-bootstrap-diagnostic/native_field_reborrow_check.sh
	@bash test/native-bootstrap-diagnostic/native_switch_default_check.sh
	@bash test/native-bootstrap-diagnostic/native_frontend_parser_check.sh
	@bash test/native-bootstrap-diagnostic/native_records_check.sh
	@bash test/native-bootstrap-diagnostic/native_record_preflight_check.sh
	@bash test/native-bootstrap-diagnostic/native_record_rollback_check.sh
	@bash test/native-bootstrap-diagnostic/native_record_borrow_check.sh
	@bash test/native-bootstrap-diagnostic/native_record_loop_borrow_check.sh
	@bash test/native-bootstrap-diagnostic/native_discard_borrow_check.sh
	@bash test/native-bootstrap-diagnostic/native_recursive_ast_borrow_check.sh
	@bash test/native-bootstrap-diagnostic/native_record_import_check.sh
	@bash test/native-bootstrap-diagnostic/native_import_return_check.sh
	@bash test/native-bootstrap-diagnostic/native_array_element_check.sh
	@bash test/native-bootstrap-diagnostic/native_record_receiver_check.sh
	@bash test/native-bootstrap-diagnostic/native_syntax_lexer_check.sh

.PHONY: selfhost-native-unit-check
selfhost-native-unit-check: seed-compiler-bin
	@bash test/native-bootstrap-diagnostic/native_unit_check.sh
	@bash test/native-bootstrap-diagnostic/native_unit_pipeline_check.sh
	@bash test/native-bootstrap-diagnostic/native_unit_ssa_check.sh

.PHONY: selfhost-native-import-return-check
selfhost-native-import-return-check: seed-compiler-bin
	@bash test/native-bootstrap-diagnostic/native_import_return_check.sh

.PHONY: selfhost-native-array-element-check
selfhost-native-array-element-check: seed-compiler-bin
	@bash test/native-bootstrap-diagnostic/native_array_element_check.sh

.PHONY: selfhost-native-option-payload-check
selfhost-native-option-payload-check: seed-compiler-bin
	@bash test/native-bootstrap-diagnostic/native_option_payload_check.sh

.PHONY: selfhost-native-global-check selfhost-native-fs-check
selfhost-native-global-check: seed-compiler-bin
	@bash test/native-bootstrap-diagnostic/native_global_state_check.sh

selfhost-native-fs-check: seed-compiler-bin
	@bash test/native-bootstrap-diagnostic/native_fs_result_check.sh

.PHONY: selfhost-native-string-check
selfhost-native-string-check: seed-compiler-bin
	@bash test/native-bootstrap-diagnostic/native_string_index_check.sh

.PHONY: selfhost-canonical-mir-check
selfhost-canonical-mir-check: compiler
	@bash test/native-bootstrap-diagnostic/canonical_mir_public_check.sh

.PHONY: selfhost-native-discard-check
selfhost-native-discard-check: seed-compiler-bin
	@bash test/native-bootstrap-diagnostic/native_discard_borrow_check.sh

.PHONY: selfhost-native-contains-check
selfhost-native-contains-check: seed-compiler-bin
	@bash test/native-bootstrap-diagnostic/native_contains_text_check.sh

.PHONY: selfhost-canonical-parser-check
selfhost-canonical-parser-check: seed-compiler-bin
	@bash test/native-bootstrap-diagnostic/canonical_parser_ast_check.sh
	@bash test/native-bootstrap-diagnostic/canonical_struct_ast_check.sh
	@bash test/native-bootstrap-diagnostic/canonical_control_ast_check.sh
	@bash test/native-bootstrap-diagnostic/canonical_declaration_ast_check.sh
	@bash test/native-bootstrap-diagnostic/canonical_precedence_ast_check.sh
	@bash test/native-bootstrap-diagnostic/canonical_record_ast_check.sh
	@bash test/native-bootstrap-diagnostic/canonical_array_ast_check.sh
	@bash test/native-bootstrap-diagnostic/canonical_switch_ast_check.sh

.PHONY: selfhost-canonical-production-check
selfhost-canonical-production-check: compiler selfhost-canonical-parser-check
	@bash test/native-bootstrap-diagnostic/canonical_typesys_check.sh
	@bash test/native-bootstrap-diagnostic/canonical_diagnostics_check.sh
	@bash test/native-bootstrap-diagnostic/canonical_semantic_ast_check.sh
	@bash test/native-bootstrap-diagnostic/canonical_record_semantic_check.sh
	@bash test/native-bootstrap-diagnostic/canonical_array_semantic_check.sh
	@bash test/native-bootstrap-diagnostic/canonical_enum_mir_check.sh
	@bash test/native-bootstrap-diagnostic/canonical_aggregate_mir_check.sh
	@bash test/native-bootstrap-diagnostic/canonical_cfg_mir_check.sh
	@bash test/native-bootstrap-diagnostic/canonical_semantic_production_check.sh
	@bash test/native-bootstrap-diagnostic/canonical_mir_public_check.sh
	@bash test/native-bootstrap-diagnostic/canonical_enum_production_check.sh
	@bash test/native-bootstrap-diagnostic/canonical_record_production_check.sh
	@bash test/native-bootstrap-diagnostic/canonical_array_production_check.sh
	@bash test/native-bootstrap-diagnostic/canonical_bool_production_check.sh
	@bash test/native-bootstrap-diagnostic/canonical_cfg_production_check.sh
	@bash test/native-bootstrap-diagnostic/canonical_store_production_check.sh
