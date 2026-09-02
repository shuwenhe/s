PREFIX ?= $(HOME)/.local
INSTALL_BIN_DIR ?= $(PREFIX)/bin
INSTALL_PROGRAM ?= install
SUDO ?=
SELFHOST_DIR ?= $(CURDIR)/.bootstrap/selfhost
BOOTSTRAP_MANIFEST ?= $(SELFHOST_DIR)/manifest.txt
PARALLEL_JOBS ?= $(shell nproc 2>/dev/null || echo 4)

run: bin/s
	@echo "Installing S compiler bootstrap binary (bin/s) for $$(uname -m)..."
	@mkdir -p "$(INSTALL_BIN_DIR)"
	@echo "Installing bin/s to $(INSTALL_BIN_DIR)/s..."
	@$(SUDO) $(INSTALL_PROGRAM) -m 0755 ./bin/s "$(INSTALL_BIN_DIR)/s"
	@echo "S compiler installed successfully."

build-x86_64: bin/s
	@echo "✓ S compiler ready for x86_64 (bootstrap: bin/s)"

build-arm64: bin/s
	@echo "✓ S compiler ready for ARM64 (bootstrap: bin/s)"

bin/s:
	@echo "error: bin/s not found. Please run: git clone --depth 1 https://github.com/shuwenhe/s.git"
	@exit 1

seed-tests:
	@echo "Building seed runtime/parser tests..."
	@mkdir -p ./bin
	@gcc -std=c11 -Wall -Wextra -Werror -DSEED_COMPILE_ONLY \
	  -o ./bin/seed_tests \
	  src/cmd/compile/seed/testing/tests.c \
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
	  src/cmd/compile/seed/runtime/runtime.c
	@./bin/seed_tests

seed-enum-check: seed-compiler-bin
	@./bin/s_seed test/selfhost/bootstrap_enum_seed.s /tmp/s_enum_seed.ir
	@rg -q '^RET\\|42\\|' /tmp/s_enum_seed.ir
	@echo "seed enum lowering passed"

seed-runtime-regression-bin:
	@echo "Building seed runtime regression tests..."
	@mkdir -p ./bin
	@gcc -std=c11 -Wall -Wextra -Werror -pthread -DSEED_COMPILE_ONLY \
	  -o ./bin/seed_runtime_regression \
	  src/cmd/compile/seed/testing/runtime_regression.c \
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
	  src/cmd/compile/seed/runtime/runtime.c

seed-runtime-regression: seed-runtime-regression-bin
	@./bin/seed_runtime_regression

seed-network-tests: seed-runtime-regression-bin
	@./bin/seed_runtime_regression --network-only

sroutine-check: selfhost
	@mkdir -p /tmp/s_sroutine_check
	@./bin/s src/runtime/sroutine_abi.s /tmp/s_sroutine_check/sroutine_abi.ir
	@test -s /tmp/s_sroutine_check/sroutine_abi.ir
	@./bin/s src/net/sroutine_demo.s /tmp/s_sroutine_check/sroutine_demo.ir
	@test -s /tmp/s_sroutine_check/sroutine_demo.ir
	@./bin/s --emit-bin /tmp/s_sroutine_check/sroutine_demo.ir /tmp/s_sroutine_check/sroutine_demo
	@/tmp/s_sroutine_check/sroutine_demo
	@./bin/s test/runtime/sroutine_abi_test.s /tmp/s_sroutine_check/sroutine_abi_test.ir
	@test -s /tmp/s_sroutine_check/sroutine_abi_test.ir
	@./bin/s --emit-bin /tmp/s_sroutine_check/sroutine_abi_test.ir /tmp/s_sroutine_check/sroutine_abi_test
	@/tmp/s_sroutine_check/sroutine_abi_test
	@./bin/s test/runtime/sroutine_deadlock_test.s /tmp/s_sroutine_check/sroutine_deadlock_test.ir
	@test -s /tmp/s_sroutine_check/sroutine_deadlock_test.ir
	@./bin/s --emit-bin /tmp/s_sroutine_check/sroutine_deadlock_test.ir /tmp/s_sroutine_check/sroutine_deadlock_test
	@if /tmp/s_sroutine_check/sroutine_deadlock_test >/tmp/s_sroutine_check/deadlock.out 2>&1; then \
		echo "expected sroutine deadlock detection"; exit 1; \
	else \
		rg -q "channel deadlock" /tmp/s_sroutine_check/deadlock.out; \
	fi

seed-compiler-bin:
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

seed-c-abi-test: seed-compiler-bin
	@mkdir -p /tmp/s_seed_c_abi_test
	@./bin/s_seed test/c_abi/add.s /tmp/s_seed_c_abi_test/add.ir
	@S_SOURCE_ROOT=$(CURDIR) ./bin/s_seed --emit-shared /tmp/s_seed_c_abi_test/add.ir /tmp/s_seed_c_abi_test/libs_add.$$(if [ "$$(uname -s)" = Darwin ]; then echo dylib; else echo so; fi)
	@gcc -std=c11 -Wall -Wextra -Werror -o /tmp/s_seed_c_abi_test/caller test/c_abi/caller.c $$(if [ "$$(uname -s)" = Darwin ]; then echo; else echo -ldl; fi)
	@/tmp/s_seed_c_abi_test/caller /tmp/s_seed_c_abi_test/libs_add.$$(if [ "$$(uname -s)" = Darwin ]; then echo dylib; else echo so; fi)

.PHONY: seed-module-link-test
seed-module-link-test: seed-compiler-bin
	@mkdir -p /tmp/s_seed_module_link_test
	@./bin/s_seed test/modules/provider.s /tmp/s_seed_module_link_test/provider.ir
	@./bin/s_seed test/modules/main.s /tmp/s_seed_module_link_test/main.ir
	@./bin/s_seed --link-ir /tmp/s_seed_module_link_test/program.ir /tmp/s_seed_module_link_test/provider.ir /tmp/s_seed_module_link_test/main.ir
	@! ./bin/s_seed --link-ir /tmp/s_seed_module_link_test/duplicate.ir /tmp/s_seed_module_link_test/provider.ir /tmp/s_seed_module_link_test/provider.ir >/dev/null 2>&1
	@S_SOURCE_ROOT=$(CURDIR) ./bin/s_seed --emit-bin /tmp/s_seed_module_link_test/program.ir /tmp/s_seed_module_link_test/program
	@/tmp/s_seed_module_link_test/program
	@echo "Seed multi-module IR link test passed."

.PHONY: seed-frontend-lexer-check
seed-frontend-lexer-check: seed-compiler-bin
	@mkdir -p /tmp/s_seed_frontend_check
	@./bin/s_seed src/cmd/compile/internal/frontend/lexer.s /tmp/s_seed_frontend_check/lexer.ir
	@test -s /tmp/s_seed_frontend_check/lexer.ir
	@rg -q '^CALL\|.*__string_len\|' /tmp/s_seed_frontend_check/lexer.ir
	@rg -q '^PARAM\|lex\|' /tmp/s_seed_frontend_check/lexer.ir
	@echo "Seed frontend lexer IR check passed"

.PHONY: seed-frontend-parser-check
seed-frontend-parser-check: seed-compiler-bin seed-frontend-lexer-check
	@./bin/s_seed src/cmd/compile/internal/frontend/parser.s /tmp/s_seed_frontend_check/parser.ir
	@test -s /tmp/s_seed_frontend_check/parser.ir
	@rg -q '^CALL\|.*parser_next_token\|' /tmp/s_seed_frontend_check/parser.ir
	@echo "Seed frontend parser IR check passed"

bootstrap-stage0: seed-compiler-bin
	@echo "Bootstrap stage0 ready: ./bin/s_seed (trusted C seed)"

bootstrap-capability-report: seed-compiler-bin
	@mkdir -p $(SELFHOST_DIR)/capability
	@./bin/s_seed src/cmd/compile/selfhost/compiler.s $(SELFHOST_DIR)/capability/compiler.ir
	@S_SOURCE_ROOT=$(CURDIR) ./bin/s_seed --emit-standalone-amd64 \
	  $(SELFHOST_DIR)/capability/compiler.ir $(SELFHOST_DIR)/capability/compiler
	@$(SELFHOST_DIR)/capability/compiler --report-unsupported \
	  src/cmd/compile/selfhost/compiler.s $(SELFHOST_DIR)/capability/unsupported.txt
	@! grep -q '|package|' $(SELFHOST_DIR)/capability/unsupported.txt
	@$(SELFHOST_DIR)/capability/compiler --emit-native \
	  test/selfhost/bootstrap_package_valid.s $(SELFHOST_DIR)/capability/package-valid
	@set +e; $(SELFHOST_DIR)/capability/package-valid; status=$$?; set -e; test $$status -eq 42
	@! $(SELFHOST_DIR)/capability/compiler --emit-native \
	  test/selfhost/bootstrap_package_invalid.s $(SELFHOST_DIR)/capability/package-invalid >/dev/null 2>&1
	@! grep -q '|extern-intrinsic|' $(SELFHOST_DIR)/capability/unsupported.txt
	@$(SELFHOST_DIR)/capability/compiler --emit-native \
	  test/selfhost/bootstrap_intrinsic_valid.s $(SELFHOST_DIR)/capability/intrinsic-valid
	@set +e; $(SELFHOST_DIR)/capability/intrinsic-valid; status=$$?; set -e; test $$status -eq 42
	@! $(SELFHOST_DIR)/capability/compiler --emit-native \
	  test/selfhost/bootstrap_intrinsic_invalid.s $(SELFHOST_DIR)/capability/intrinsic-invalid >/dev/null 2>&1
	@! grep -q '|bool|' $(SELFHOST_DIR)/capability/unsupported.txt
	@$(SELFHOST_DIR)/capability/compiler --emit-native \
	  test/selfhost/bootstrap_bool_cross_function.s $(SELFHOST_DIR)/capability/bool-cross-function
	@set +e; $(SELFHOST_DIR)/capability/bool-cross-function; status=$$?; set -e; test $$status -eq 42
	@if grep -q '|string|' $(SELFHOST_DIR)/capability/unsupported.txt; then \
	  echo "string capability is still reported unsupported" >&2; exit 1; \
	fi
	@$(SELFHOST_DIR)/capability/compiler --emit-native \
	  test/selfhost/bootstrap_string_abi_length.s $(SELFHOST_DIR)/capability/string-abi-length
	@$(SELFHOST_DIR)/capability/compiler --emit-native \
	  test/selfhost/bootstrap_string_abi_local.s $(SELFHOST_DIR)/capability/string-abi-local
	@$(SELFHOST_DIR)/capability/compiler --emit-native \
	  test/selfhost/bootstrap_string_abi_branch.s $(SELFHOST_DIR)/capability/string-abi-branch
	@set +e; $(SELFHOST_DIR)/capability/string-abi-length; status=$$?; set -e; test $$status -eq 42
	@set +e; $(SELFHOST_DIR)/capability/string-abi-local; status=$$?; set -e; test $$status -eq 42
	@set +e; $(SELFHOST_DIR)/capability/string-abi-branch; status=$$?; set -e; test $$status -eq 42
	@if grep -q '|multiple-functions|' $(SELFHOST_DIR)/capability/unsupported.txt; then \
	  echo "whole-program capability is still reported unsupported" >&2; exit 1; \
	fi
	@$(SELFHOST_DIR)/capability/compiler --emit-native \
	  test/selfhost/bootstrap_whole_program.s $(SELFHOST_DIR)/capability/whole-program
	@set +e; $(SELFHOST_DIR)/capability/whole-program; status=$$?; set -e; test $$status -eq 42
	@! $(SELFHOST_DIR)/capability/compiler --emit-native \
	  test/selfhost/bootstrap_duplicate_function.s $(SELFHOST_DIR)/capability/duplicate-function >/dev/null 2>&1
	@! $(SELFHOST_DIR)/capability/compiler --emit-native \
	  test/selfhost/bootstrap_invalid_signature.s $(SELFHOST_DIR)/capability/invalid-signature >/dev/null 2>&1
	@! $(SELFHOST_DIR)/capability/compiler --emit-native \
	  test/selfhost/bootstrap_unknown_function.s $(SELFHOST_DIR)/capability/unknown-function >/dev/null 2>&1
	@$(SELFHOST_DIR)/capability/compiler --emit-native \
	  test/selfhost/bootstrap_intrinsic_string_arg.s $(SELFHOST_DIR)/capability/intrinsic-string-arg
	@$(SELFHOST_DIR)/capability/compiler --emit-native \
	  test/selfhost/bootstrap_intrinsic_string_return.s $(SELFHOST_DIR)/capability/intrinsic-string-return
	@$(SELFHOST_DIR)/capability/compiler --emit-native \
	  test/selfhost/bootstrap_intrinsic_scalar_return.s $(SELFHOST_DIR)/capability/intrinsic-scalar-return
	@set +e; $(SELFHOST_DIR)/capability/intrinsic-string-arg; status=$$?; set -e; test $$status -eq 42
	@set +e; $(SELFHOST_DIR)/capability/intrinsic-string-return; status=$$?; set -e; test $$status -eq 42
	@set +e; $(SELFHOST_DIR)/capability/intrinsic-scalar-return; status=$$?; set -e; test $$status -eq 42
	@grep -q '^semantic|.*|for-loop|' $(SELFHOST_DIR)/capability/unsupported.txt
	@grep -q '^codegen|.*|stack-arguments|' $(SELFHOST_DIR)/capability/unsupported.txt
	@echo "Bootstrap capability report: $(SELFHOST_DIR)/capability/unsupported.txt"

bootstrap-convergence: bootstrap-stage0
	@mkdir -p $(SELFHOST_DIR) ./bin
	@S_SOURCE_ROOT=$(CURDIR) ./bin/s_seed --bootstrap src/cmd/compile/main.s $(SELFHOST_DIR)
	@./src/cmd/dist/checks/write-manifest.sh "$(SELFHOST_DIR)" "$(BOOTSTRAP_MANIFEST)"
	@echo "Bootstrap convergence passed: stage2.ir == stage3.ir"

bootstrap-pure-s: bootstrap-stage0
	@S_SOURCE_ROOT=$(CURDIR) ./src/cmd/dist/native-bootstrap.sh \
	  $(SELFHOST_DIR)

# The seed is allowed to construct stage1 only. native-bootstrap then uses
# stage1 and stage2 to generate stage2 and stage3 without invoking the seed.
selfhost: native-bootstrap
	@$(INSTALL_PROGRAM) -m 0755 $(SELFHOST_DIR)/native/stage2 ./bin/s
	@echo "Installed S self-hosted compiler: ./bin/s"
	@echo "Verified bootstrap chain: seed -> stage1 -> stage2 -> stage3"

seed-hosted-selfhost: bootstrap-convergence
	@$(INSTALL_PROGRAM) -m 0755 $(SELFHOST_DIR)/stage2 ./bin/s
	@echo "Installed seed-hosted S compiler: ./bin/s"
	@echo "Note: this artifact is not yet a true native self-hosted compiler"

native-selfhost: selfhost

selfhost-lexer-check: seed-compiler-bin
	@mkdir -p $(SELFHOST_DIR) ./bin
	@./bin/s_seed src/cmd/compile/selfhost/lexer.s $(SELFHOST_DIR)/lexer.ir
	@S_SOURCE_ROOT=$(CURDIR) ./bin/s_seed --emit-standalone-amd64 $(SELFHOST_DIR)/lexer.ir $(SELFHOST_DIR)/s_lexer
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/s_lexer
	@./bin/s_seed --dump-tokens test/selfhost/lexer_fixture.s $(SELFHOST_DIR)/tokens.seed
	@$(SELFHOST_DIR)/s_lexer test/selfhost/lexer_fixture.s $(SELFHOST_DIR)/tokens.s
	@cmp $(SELFHOST_DIR)/tokens.seed $(SELFHOST_DIR)/tokens.s
	@./bin/s_seed --dump-tokens test/selfhost/lexer_unterminated_string.s $(SELFHOST_DIR)/unterminated-string.seed
	@$(SELFHOST_DIR)/s_lexer test/selfhost/lexer_unterminated_string.s $(SELFHOST_DIR)/unterminated-string.s
	@cmp $(SELFHOST_DIR)/unterminated-string.seed $(SELFHOST_DIR)/unterminated-string.s
	@./bin/s_seed --dump-tokens test/selfhost/lexer_unterminated_comment.s $(SELFHOST_DIR)/unterminated-comment.seed
	@$(SELFHOST_DIR)/s_lexer test/selfhost/lexer_unterminated_comment.s $(SELFHOST_DIR)/unterminated-comment.s
	@cmp $(SELFHOST_DIR)/unterminated-comment.seed $(SELFHOST_DIR)/unterminated-comment.s
	@./bin/s_seed --dump-tokens test/selfhost/lexer_illegal_char.s $(SELFHOST_DIR)/illegal-char.seed
	@$(SELFHOST_DIR)/s_lexer test/selfhost/lexer_illegal_char.s $(SELFHOST_DIR)/illegal-char.s
	@cmp $(SELFHOST_DIR)/illegal-char.seed $(SELFHOST_DIR)/illegal-char.s
	@$(INSTALL_PROGRAM) -m 0755 $(SELFHOST_DIR)/s_lexer ./bin/s_lexer
	@echo "Standalone S lexer check passed: S token stream == seed token stream"

selfhost-check: selfhost selfhost-lexer-check
	@./bin/s test/c_abi/add.s $(SELFHOST_DIR)/final-check.ir
	@S_LEXER_MODE=selfhost S_SELFHOST_LEXER=$(SELFHOST_DIR)/s_lexer ./bin/s test/c_abi/add.s $(SELFHOST_DIR)/s-lexer-parser.ir
	@cmp $(SELFHOST_DIR)/final-check.ir $(SELFHOST_DIR)/s-lexer-parser.ir
	@cmp $(SELFHOST_DIR)/native/stage2.S $(SELFHOST_DIR)/native/stage3.S
	@echo "Native bootstrap check passed: stage2 == stage3 and S Lexer -> Parser IR matches seed"

true-selfhost-check: selfhost-check
	@./misc/scripts/verify_true_selfhost.sh ./bin/s
	@echo "True self-host check passed: ./bin/s does not link the C seed compiler"

bootstrap-audit: selfhost
	@./src/cmd/dist/checks/audit.sh "$(SELFHOST_DIR)/native" ./bin/s

# Build a genuinely independent compiler chain. Unlike bootstrap-convergence,
# this target compares S-generated assembly and compiler executables.
native-bootstrap: seed-compiler-bin
	@S_SOURCE_ROOT=$(CURDIR) ./src/cmd/dist/native-bootstrap.sh \
	  $(SELFHOST_DIR)/native

# Strict self-host gate: every stage writes the next ELF image directly. This
# target intentionally forbids the assembly/link steps used by native-bootstrap.
direct-bootstrap:
	@S_SOURCE_ROOT=$(CURDIR) ./src/cmd/dist/direct-bootstrap.sh \
	  $(SELFHOST_DIR)/direct

# Strict self-host target: produce a compiler that does not rely on the C seed
# at any later stage. Uses the `direct-bootstrap` frontier which writes ELF
# images directly and then verifies the produced compiler is a true
# self-hosted binary (no C seed linkage).
selfhost_strict: direct-bootstrap
	@$(INSTALL_PROGRAM) -m 0755 $(SELFHOST_DIR)/direct/stage2 ./bin/s
	@echo "Installed strict native self-hosted S compiler: ./bin/s"
	@./misc/scripts/verify_true_selfhost.sh ./bin/s
	@echo "Strict self-host check passed: ./bin/s does not link the C seed compiler"

native-bootstrap-install: native-bootstrap
	@$(MAKE) native-selfhost

bootstrap-subset-check: seed-compiler-bin
	@mkdir -p $(SELFHOST_DIR)/subset
	@./bin/s_seed test/selfhost/subset_valid.s $(SELFHOST_DIR)/subset/valid.ir
	@! ./bin/s_seed test/selfhost/subset_invalid_let.s $(SELFHOST_DIR)/subset/invalid-let.ir >/dev/null 2>&1
	@! ./bin/s_seed test/selfhost/subset_invalid_var.s $(SELFHOST_DIR)/subset/invalid-var.ir >/dev/null 2>&1
	@echo "Bootstrap declaration subset check passed"

# Gate the S-written direct backend separately from the assembly bootstrap.
# The seed only constructs the compiler; every test program below is emitted
# as an ELF executable directly by that S compiler without as/ld/cc.
native-codegen-check: seed-compiler-bin
	@mkdir -p $(SELFHOST_DIR)/native-codegen
	@./bin/s_seed src/cmd/compile/selfhost/compiler.s \
	  $(SELFHOST_DIR)/native-codegen/compiler.ir
	@S_SOURCE_ROOT=$(CURDIR) ./bin/s_seed --emit-standalone-amd64 \
	  $(SELFHOST_DIR)/native-codegen/compiler.ir \
	  $(SELFHOST_DIR)/native-codegen/compiler
	@./misc/scripts/verify_true_selfhost.sh \
	  $(SELFHOST_DIR)/native-codegen/compiler
	@for case_name in expr locals control call loop array logical multicall; do \
	  source_file=test/selfhost/bootstrap_native_$$case_name.s; \
	  output_file=$(SELFHOST_DIR)/native-codegen/$$case_name; \
	  $(SELFHOST_DIR)/native-codegen/compiler --emit-native \
	    $$source_file $$output_file || exit 1; \
	  ./misc/scripts/verify_true_selfhost.sh $$output_file || exit 1; \
	  set +e; timeout 5s $$output_file >/dev/null; status=$$?; set -e; \
	  test $$status -eq 42 || exit 1; \
	done
	@$(SELFHOST_DIR)/native-codegen/compiler --emit-native \
	  test/selfhost/bootstrap_native_string.s \
	  $(SELFHOST_DIR)/native-codegen/string
	@./misc/scripts/verify_true_selfhost.sh \
	  $(SELFHOST_DIR)/native-codegen/string
	@set +e; timeout 5s $(SELFHOST_DIR)/native-codegen/string \
	  >$(SELFHOST_DIR)/native-codegen/string.out; status=$$?; set -e; \
	  test $$status -eq 42
	@test "$$(cat $(SELFHOST_DIR)/native-codegen/string.out)" = "selfhost-string"
	@echo "Native codegen gate passed: S emitted runnable ELF files directly"

bootstrap-slice1-check: seed-compiler-bin
	@mkdir -p $(SELFHOST_DIR)/slice1
	@./bin/s_seed src/cmd/compile/selfhost/compiler.s $(SELFHOST_DIR)/slice1/compiler.ir
	@S_SOURCE_ROOT=$(CURDIR) ./bin/s_seed --emit-standalone-amd64 \
	  $(SELFHOST_DIR)/slice1/compiler.ir $(SELFHOST_DIR)/slice1/compiler
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice1/compiler
	@$(SELFHOST_DIR)/slice1/compiler --emit-asm test/selfhost/bootstrap_asm_string.s \
	  $(SELFHOST_DIR)/slice1/asm-string.S
	@as --64 -o $(SELFHOST_DIR)/slice1/asm-string.o $(SELFHOST_DIR)/slice1/asm-string.S
	@as --64 -o $(SELFHOST_DIR)/slice1/asm-runtime.o src/runtime/selfhost_linux_amd64.S
	@ld -static -T src/runtime/linker/nostdlib.ld -o $(SELFHOST_DIR)/slice1/asm-string \
	  $(SELFHOST_DIR)/slice1/asm-runtime.o $(SELFHOST_DIR)/slice1/asm-string.o
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice1/asm-string
	@set +e; $(SELFHOST_DIR)/slice1/asm-string; status=$$?; set -e; test $$status -eq 42
	@$(SELFHOST_DIR)/slice1/compiler test/selfhost/bootstrap_slice1.s \
	  $(SELFHOST_DIR)/slice1/program.ir
	@grep -q '^RET|42|_|_$$' $(SELFHOST_DIR)/slice1/program.ir
	@$(SELFHOST_DIR)/slice1/compiler --emit-bin test/selfhost/bootstrap_slice1.s \
	  $(SELFHOST_DIR)/slice1/program
	@$(SELFHOST_DIR)/slice1/compiler --emit-bin test/selfhost/bootstrap_slice1.s \
	  $(SELFHOST_DIR)/slice1/program.repeat
	@cmp $(SELFHOST_DIR)/slice1/program $(SELFHOST_DIR)/slice1/program.repeat
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice1/program
	@set +e; $(SELFHOST_DIR)/slice1/program; status=$$?; set -e; test $$status -eq 42
	@! $(SELFHOST_DIR)/slice1/compiler test/selfhost/bootstrap_slice1_divzero.s \
	  $(SELFHOST_DIR)/slice1/divzero.ir >/dev/null 2>&1
	@! $(SELFHOST_DIR)/slice1/compiler test/selfhost/bootstrap_slice1_malformed.s \
	  $(SELFHOST_DIR)/slice1/malformed.ir >/dev/null 2>&1
	@! $(SELFHOST_DIR)/slice1/compiler test/selfhost/bootstrap_slice1_no_return.s \
	  $(SELFHOST_DIR)/slice1/no-return.ir >/dev/null 2>&1
	@$(SELFHOST_DIR)/slice1/compiler test/selfhost/bootstrap_slice1_binding.s \
	  $(SELFHOST_DIR)/slice1/binding.ir
	@grep -q '^RET|42|_|_$$' $(SELFHOST_DIR)/slice1/binding.ir
	@$(SELFHOST_DIR)/slice1/compiler test/selfhost/bootstrap_slice1_control.s \
	  $(SELFHOST_DIR)/slice1/control.ir
	@grep -q '^RET|42|_|_$$' $(SELFHOST_DIR)/slice1/control.ir
	@$(SELFHOST_DIR)/slice1/compiler --emit-native test/selfhost/bootstrap_native_expr.s \
	  $(SELFHOST_DIR)/slice1/native-expression
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice1/native-expression
	@set +e; $(SELFHOST_DIR)/slice1/native-expression; status=$$?; set -e; test $$status -eq 42
	@objdump -D -b binary -m i386:x86-64 $(SELFHOST_DIR)/slice1/native-expression | grep -q 'imul'
	@$(SELFHOST_DIR)/slice1/compiler --emit-native test/selfhost/bootstrap_native_control.s \
	  $(SELFHOST_DIR)/slice1/native-control
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice1/native-control
	@set +e; $(SELFHOST_DIR)/slice1/native-control; status=$$?; set -e; test $$status -eq 42
	@objdump -D -b binary -m i386:x86-64 $(SELFHOST_DIR)/slice1/native-control | grep -q 'je'
	@$(SELFHOST_DIR)/slice1/compiler --emit-native test/selfhost/bootstrap_native_control_nested.s \
	  $(SELFHOST_DIR)/slice1/native-control-nested
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice1/native-control-nested
	@set +e; $(SELFHOST_DIR)/slice1/native-control-nested; status=$$?; set -e; test $$status -eq 42
	@$(SELFHOST_DIR)/slice1/compiler --emit-native test/selfhost/bootstrap_native_locals.s \
	  $(SELFHOST_DIR)/slice1/native-locals
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice1/native-locals
	@set +e; $(SELFHOST_DIR)/slice1/native-locals; status=$$?; set -e; test $$status -eq 42
	@objdump -D -b binary -m i386:x86-64 $(SELFHOST_DIR)/slice1/native-locals | grep -q '(%rbp)'
	@$(SELFHOST_DIR)/slice1/compiler --emit-native test/selfhost/bootstrap_native_call.s \
	  $(SELFHOST_DIR)/slice1/native-call
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice1/native-call
	@set +e; $(SELFHOST_DIR)/slice1/native-call; status=$$?; set -e; test $$status -eq 42
	@objdump -D -b binary -m i386:x86-64 $(SELFHOST_DIR)/slice1/native-call | grep -q 'call.*%rax'
	@$(SELFHOST_DIR)/slice1/compiler --emit-native test/selfhost/bootstrap_native_call6.s \
	  $(SELFHOST_DIR)/slice1/native-call6
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice1/native-call6
	@set +e; $(SELFHOST_DIR)/slice1/native-call6; status=$$?; set -e; test $$status -eq 42
	@objdump -D -b binary -m i386:x86-64 $(SELFHOST_DIR)/slice1/native-call6 | grep -q '%r9'
	@$(SELFHOST_DIR)/slice1/compiler --emit-native test/selfhost/bootstrap_native_loop.s \
	  $(SELFHOST_DIR)/slice1/native-loop
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice1/native-loop
	@set +e; $(SELFHOST_DIR)/slice1/native-loop; status=$$?; set -e; test $$status -eq 42
	@objdump -D -b binary -m i386:x86-64 $(SELFHOST_DIR)/slice1/native-loop | grep -q 'jmp'
	@$(SELFHOST_DIR)/slice1/compiler --emit-native test/selfhost/bootstrap_native_string.s \
	  $(SELFHOST_DIR)/slice1/native-string
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice1/native-string
	@set +e; $(SELFHOST_DIR)/slice1/native-string >$(SELFHOST_DIR)/slice1/native-string.out; status=$$?; set -e; test $$status -eq 42
	@test "$$(cat $(SELFHOST_DIR)/slice1/native-string.out)" = "selfhost-string"
	@$(SELFHOST_DIR)/slice1/compiler --emit-native test/selfhost/bootstrap_native_array.s \
	  $(SELFHOST_DIR)/slice1/native-array
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice1/native-array
	@set +e; $(SELFHOST_DIR)/slice1/native-array; status=$$?; set -e; test $$status -eq 42
	@$(SELFHOST_DIR)/slice1/compiler --emit-native test/selfhost/bootstrap_native_multicall.s \
	  $(SELFHOST_DIR)/slice1/native-multicall
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice1/native-multicall
	@set +e; $(SELFHOST_DIR)/slice1/native-multicall; status=$$?; set -e; test $$status -eq 42
	@test "$$(objdump -D -b binary -m i386:x86-64 $(SELFHOST_DIR)/slice1/native-multicall | grep -c 'call.*%rax')" -ge 2
	@$(SELFHOST_DIR)/slice1/compiler --emit-native test/selfhost/bootstrap_native_multicall_args.s \
	  $(SELFHOST_DIR)/slice1/native-multicall-args
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice1/native-multicall-args
	@set +e; $(SELFHOST_DIR)/slice1/native-multicall-args; status=$$?; set -e; test $$status -eq 42
	@test "$$(objdump -D -b binary -m i386:x86-64 $(SELFHOST_DIR)/slice1/native-multicall-args | grep -c 'call.*%rax')" -ge 2
	@$(SELFHOST_DIR)/slice1/compiler --emit-native test/selfhost/bootstrap_native_function_loop.s \
	  $(SELFHOST_DIR)/slice1/native-function-loop
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice1/native-function-loop
	@set +e; $(SELFHOST_DIR)/slice1/native-function-loop; status=$$?; set -e; test $$status -eq 42
	@objdump -D -b binary -m i386:x86-64 $(SELFHOST_DIR)/slice1/native-function-loop | grep -q 'jmp'
	@$(SELFHOST_DIR)/slice1/compiler --emit-native test/selfhost/bootstrap_native_function_control.s \
	  $(SELFHOST_DIR)/slice1/native-function-control
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice1/native-function-control
	@set +e; $(SELFHOST_DIR)/slice1/native-function-control; status=$$?; set -e; test $$status -eq 42
	@objdump -D -b binary -m i386:x86-64 $(SELFHOST_DIR)/slice1/native-function-control | grep -q 'je'
	@$(SELFHOST_DIR)/slice1/compiler --emit-native test/selfhost/bootstrap_native_logical.s \
	  $(SELFHOST_DIR)/slice1/native-logical
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice1/native-logical
	@set +e; $(SELFHOST_DIR)/slice1/native-logical; status=$$?; set -e; test $$status -eq 42
	@$(SELFHOST_DIR)/slice1/compiler --emit-native test/selfhost/bootstrap_native_typed_locals.s \
	  $(SELFHOST_DIR)/slice1/native-typed-locals
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice1/native-typed-locals
	@set +e; $(SELFHOST_DIR)/slice1/native-typed-locals; status=$$?; set -e; test $$status -eq 42
	@$(SELFHOST_DIR)/slice1/compiler --emit-native test/selfhost/bootstrap_native_large_function.s \
	  $(SELFHOST_DIR)/slice1/native-large-function
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice1/native-large-function
	@set +e; $(SELFHOST_DIR)/slice1/native-large-function; status=$$?; set -e; test $$status -eq 42
	@$(SELFHOST_DIR)/slice1/compiler --emit-native test/selfhost/bootstrap_native_copy.s \
	  $(SELFHOST_DIR)/slice1/native-copy
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice1/native-copy
	@set +e; $(SELFHOST_DIR)/slice1/native-copy; status=$$?; set -e; test $$status -eq 2
	@set +e; $(SELFHOST_DIR)/slice1/native-copy $(SELFHOST_DIR)/slice1/missing-input \
	  $(SELFHOST_DIR)/slice1/missing-output; status=$$?; set -e; test $$status -eq 1
	@$(SELFHOST_DIR)/slice1/native-copy test/selfhost/bootstrap_native_copy_input.txt \
	  $(SELFHOST_DIR)/slice1/native-copy.out
	@cmp test/selfhost/bootstrap_native_copy_input.txt $(SELFHOST_DIR)/slice1/native-copy.out
	@$(SELFHOST_DIR)/slice1/native-copy src/cmd/compile/selfhost/compiler.s \
	  $(SELFHOST_DIR)/slice1/native-copy-large.out
	@cmp src/cmd/compile/selfhost/compiler.s $(SELFHOST_DIR)/slice1/native-copy-large.out
	@! $(SELFHOST_DIR)/slice1/compiler --emit-native src/cmd/compile/selfhost/compiler.s \
	  $(SELFHOST_DIR)/slice1/not-yet-selfhosted >/dev/null 2>&1
	@echo "Bootstrap slice 1 passed: static S compiler produced a runnable program"

bootstrap-slice2-check: seed-compiler-bin
	@mkdir -p $(SELFHOST_DIR)/slice2
	@./bin/s_seed src/cmd/compile/selfhost/compiler.s $(SELFHOST_DIR)/slice2/compiler.ir
	@S_SOURCE_ROOT=$(CURDIR) ./bin/s_seed --emit-standalone-amd64 \
	  $(SELFHOST_DIR)/slice2/compiler.ir $(SELFHOST_DIR)/slice2/compiler
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice2/compiler
	@$(SELFHOST_DIR)/slice2/compiler --emit-native test/selfhost/bootstrap_native_expr.s \
	  $(SELFHOST_DIR)/slice2/native-expression
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice2/native-expression
	@set +e; $(SELFHOST_DIR)/slice2/native-expression; status=$$?; set -e; test $$status -eq 42
	@$(SELFHOST_DIR)/slice2/compiler --emit-native test/selfhost/bootstrap_native_control.s \
	  $(SELFHOST_DIR)/slice2/native-control
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice2/native-control
	@set +e; $(SELFHOST_DIR)/slice2/native-control; status=$$?; set -e; test $$status -eq 42
	@$(SELFHOST_DIR)/slice2/compiler --emit-native test/selfhost/bootstrap_native_locals.s \
	  $(SELFHOST_DIR)/slice2/native-locals
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice2/native-locals
	@set +e; $(SELFHOST_DIR)/slice2/native-locals; status=$$?; set -e; test $$status -eq 42
	@sh ./src/cmd/dist/checks/bootstrap-frontier.sh src/cmd/compile/selfhost/compiler.s
	@echo "Bootstrap slice 2 passed: native expression/control/locals frontier"

bootstrap-slice3-check: seed-compiler-bin
	@mkdir -p $(SELFHOST_DIR)/slice3
	@./bin/s_seed src/cmd/compile/selfhost/compiler.s $(SELFHOST_DIR)/slice3/compiler.ir
	@S_SOURCE_ROOT=$(CURDIR) ./bin/s_seed --emit-standalone-amd64 \
	  $(SELFHOST_DIR)/slice3/compiler.ir $(SELFHOST_DIR)/slice3/compiler
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice3/compiler
	@$(SELFHOST_DIR)/slice3/compiler --emit-native test/selfhost/bootstrap_native_call.s \
	  $(SELFHOST_DIR)/slice3/native-call
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice3/native-call
	@set +e; $(SELFHOST_DIR)/slice3/native-call; status=$$?; set -e; test $$status -eq 42
	@$(SELFHOST_DIR)/slice3/compiler --emit-native test/selfhost/bootstrap_native_loop.s \
	  $(SELFHOST_DIR)/slice3/native-loop
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice3/native-loop
	@set +e; $(SELFHOST_DIR)/slice3/native-loop; status=$$?; set -e; test $$status -eq 42
	@$(SELFHOST_DIR)/slice3/compiler --emit-native test/selfhost/bootstrap_native_string.s \
	  $(SELFHOST_DIR)/slice3/native-string
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice3/native-string
	@set +e; $(SELFHOST_DIR)/slice3/native-string >$(SELFHOST_DIR)/slice3/native-string.out; status=$$?; set -e; test $$status -eq 42
	@test "$$(cat $(SELFHOST_DIR)/slice3/native-string.out)" = "selfhost-string"
	@$(SELFHOST_DIR)/slice3/compiler --emit-native test/selfhost/bootstrap_native_array.s \
	  $(SELFHOST_DIR)/slice3/native-array
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice3/native-array
	@set +e; $(SELFHOST_DIR)/slice3/native-array; status=$$?; set -e; test $$status -eq 42
	@$(SELFHOST_DIR)/slice3/compiler --emit-native test/selfhost/bootstrap_native_multicall.s \
	  $(SELFHOST_DIR)/slice3/native-multicall
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice3/native-multicall
	@set +e; $(SELFHOST_DIR)/slice3/native-multicall; status=$$?; set -e; test $$status -eq 42
	@test "$$(objdump -D -b binary -m i386:x86-64 $(SELFHOST_DIR)/slice3/native-multicall | grep -c 'call.*%rax')" -ge 2
	@$(SELFHOST_DIR)/slice3/compiler --emit-native test/selfhost/bootstrap_native_multicall_args.s \
	  $(SELFHOST_DIR)/slice3/native-multicall-args
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice3/native-multicall-args
	@set +e; $(SELFHOST_DIR)/slice3/native-multicall-args; status=$$?; set -e; test $$status -eq 42
	@test "$$(objdump -D -b binary -m i386:x86-64 $(SELFHOST_DIR)/slice3/native-multicall-args | grep -c 'call.*%rax')" -ge 2
	@$(SELFHOST_DIR)/slice3/compiler --emit-native test/selfhost/bootstrap_native_copy.s \
	  $(SELFHOST_DIR)/slice3/native-copy
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice3/native-copy
	@set +e; $(SELFHOST_DIR)/slice3/native-copy; status=$$?; set -e; test $$status -eq 2
	@set +e; $(SELFHOST_DIR)/slice3/native-copy $(SELFHOST_DIR)/slice3/missing-input \
	  $(SELFHOST_DIR)/slice3/missing-output; status=$$?; set -e; test $$status -eq 1
	@$(SELFHOST_DIR)/slice3/native-copy test/selfhost/bootstrap_native_copy_input.txt \
	  $(SELFHOST_DIR)/slice3/native-copy.out
	@cmp test/selfhost/bootstrap_native_copy_input.txt $(SELFHOST_DIR)/slice3/native-copy.out
	@echo "Bootstrap slice 3 passed: native call/loop/string/array/multicall/copy frontier"

bootstrap-slice4-check: seed-compiler-bin
	@mkdir -p $(SELFHOST_DIR)/slice4
	@./bin/s_seed src/cmd/compile/selfhost/compiler.s $(SELFHOST_DIR)/slice4/compiler.ir
	@S_SOURCE_ROOT=$(CURDIR) ./bin/s_seed --emit-standalone-amd64 \
	  $(SELFHOST_DIR)/slice4/compiler.ir $(SELFHOST_DIR)/slice4/compiler
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice4/compiler
	@$(SELFHOST_DIR)/slice4/compiler --emit-native test/selfhost/bootstrap_native_function_loop.s \
	  $(SELFHOST_DIR)/slice4/native-function-loop
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice4/native-function-loop
	@set +e; $(SELFHOST_DIR)/slice4/native-function-loop; status=$$?; set -e; test $$status -eq 42
	@$(SELFHOST_DIR)/slice4/compiler --emit-native test/selfhost/bootstrap_native_function_control.s \
	  $(SELFHOST_DIR)/slice4/native-function-control
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice4/native-function-control
	@set +e; $(SELFHOST_DIR)/slice4/native-function-control; status=$$?; set -e; test $$status -eq 42
	@$(SELFHOST_DIR)/slice4/compiler --emit-native test/selfhost/bootstrap_native_logical.s \
	  $(SELFHOST_DIR)/slice4/native-logical
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice4/native-logical
	@set +e; $(SELFHOST_DIR)/slice4/native-logical; status=$$?; set -e; test $$status -eq 42
	@$(SELFHOST_DIR)/slice4/compiler --emit-native test/selfhost/bootstrap_native_typed_locals.s \
	  $(SELFHOST_DIR)/slice4/native-typed-locals
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice4/native-typed-locals
	@set +e; $(SELFHOST_DIR)/slice4/native-typed-locals; status=$$?; set -e; test $$status -eq 42
	@$(SELFHOST_DIR)/slice4/compiler --emit-native test/selfhost/bootstrap_native_large_function.s \
	  $(SELFHOST_DIR)/slice4/native-large-function
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice4/native-large-function
	@set +e; $(SELFHOST_DIR)/slice4/native-large-function; status=$$?; set -e; test $$status -eq 42
	@echo "Bootstrap slice 4 passed: function control/logical/typed locals/large function frontier"

bootstrap-slice5-check: seed-compiler-bin
	@mkdir -p $(SELFHOST_DIR)/slice5
	@./bin/s_seed src/cmd/compile/selfhost/compiler.s $(SELFHOST_DIR)/slice5/compiler.ir
	@S_SOURCE_ROOT=$(CURDIR) ./bin/s_seed --emit-standalone-amd64 \
	  $(SELFHOST_DIR)/slice5/compiler.ir $(SELFHOST_DIR)/slice5/compiler
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice5/compiler
	@$(SELFHOST_DIR)/slice5/compiler --emit-native test/selfhost/bootstrap_native_multicall.s \
	  $(SELFHOST_DIR)/slice5/native-multicall
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice5/native-multicall
	@set +e; $(SELFHOST_DIR)/slice5/native-multicall; status=$$?; set -e; test $$status -eq 42
	@$(SELFHOST_DIR)/slice5/compiler --emit-native test/selfhost/bootstrap_native_multicall_args.s \
	  $(SELFHOST_DIR)/slice5/native-multicall-args
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice5/native-multicall-args
	@set +e; $(SELFHOST_DIR)/slice5/native-multicall-args; status=$$?; set -e; test $$status -eq 42
	@test "$$(objdump -D -b binary -m i386:x86-64 $(SELFHOST_DIR)/slice5/native-multicall | grep -c 'call.*%rax')" -ge 2
	@test "$$(objdump -D -b binary -m i386:x86-64 $(SELFHOST_DIR)/slice5/native-multicall-args | grep -c 'call.*%rax')" -ge 2
	@$(SELFHOST_DIR)/slice5/compiler --emit-native test/selfhost/bootstrap_native_call6.s \
	  $(SELFHOST_DIR)/slice5/native-call6
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice5/native-call6
	@set +e; $(SELFHOST_DIR)/slice5/native-call6; status=$$?; set -e; test $$status -eq 42
	@$(SELFHOST_DIR)/slice5/compiler --emit-native test/selfhost/bootstrap_native_call8.s \
	  $(SELFHOST_DIR)/slice5/native-call8
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice5/native-call8
	@set +e; $(SELFHOST_DIR)/slice5/native-call8; status=$$?; set -e; test $$status -eq 42
	@echo "Bootstrap slice 5 passed: multi-call and register/stack argument passing frontier"

bootstrap-slice6-check: seed-compiler-bin
	@mkdir -p $(SELFHOST_DIR)/slice6
	@./bin/s_seed src/cmd/compile/selfhost/compiler.s $(SELFHOST_DIR)/slice6/compiler.ir
	@S_SOURCE_ROOT=$(CURDIR) ./bin/s_seed --emit-standalone-amd64 \
	  $(SELFHOST_DIR)/slice6/compiler.ir $(SELFHOST_DIR)/slice6/compiler
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice6/compiler
	@as --64 -o $(SELFHOST_DIR)/slice6/asm-runtime.o src/runtime/selfhost_linux_amd64.S
	@$(SELFHOST_DIR)/slice6/compiler --emit-asm test/selfhost/bootstrap_asm_branch_strings.s \
	  $(SELFHOST_DIR)/slice6/branch-strings.S
	@as --64 -o $(SELFHOST_DIR)/slice6/branch-strings.o $(SELFHOST_DIR)/slice6/branch-strings.S
	@ld -static -T src/runtime/linker/nostdlib.ld -o $(SELFHOST_DIR)/slice6/branch-strings \
	  $(SELFHOST_DIR)/slice6/asm-runtime.o $(SELFHOST_DIR)/slice6/branch-strings.o
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice6/branch-strings
	@set +e; $(SELFHOST_DIR)/slice6/branch-strings; status=$$?; set -e; test $$status -eq 42
	@$(SELFHOST_DIR)/slice6/compiler --emit-asm test/selfhost/bootstrap_asm_string.s \
	  $(SELFHOST_DIR)/slice6/string-compare.S
	@as --64 -o $(SELFHOST_DIR)/slice6/string-compare.o $(SELFHOST_DIR)/slice6/string-compare.S
	@ld -static -T src/runtime/linker/nostdlib.ld -o $(SELFHOST_DIR)/slice6/string-compare \
	  $(SELFHOST_DIR)/slice6/asm-runtime.o $(SELFHOST_DIR)/slice6/string-compare.o
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/slice6/string-compare
	@set +e; $(SELFHOST_DIR)/slice6/string-compare; status=$$?; set -e; test $$status -eq 42
	@echo "Bootstrap slice 6 passed: string compare and branch-string frontier"

pure-s-bootstrap-check: native-bootstrap selfhost-runtime-check selfhost-lexer-check
	@echo "Pure-S bootstrap passed: stage2/stage3 converge without a seed dependency"

bootstrap-source-closure:
	@mkdir -p $(SELFHOST_DIR)
	@./src/cmd/dist/source_closure.sh src/cmd/compile/main.s $(SELFHOST_DIR)/sources.txt
	@echo "Bootstrap source closure: $(SELFHOST_DIR)/sources.txt"

selfhost-nostdlib:
	@if [ ! -x ./bin/s_nostdlib ]; then \
		echo "selfhost-nostdlib: missing ./bin/s_nostdlib" >&2; \
		echo "the pure-S native compiler/linker path is not implemented yet" >&2; \
		exit 1; \
	fi
	@./misc/scripts/verify_true_selfhost.sh ./bin/s_nostdlib
	@echo "Verified no-libc self-hosted compiler: ./bin/s_nostdlib"

selfhost-runtime-check:
	@mkdir -p $(SELFHOST_DIR)/nostdlib
	@as --64 -o $(SELFHOST_DIR)/nostdlib/runtime.o src/runtime/selfhost_linux_amd64.S
	@as --64 -o $(SELFHOST_DIR)/nostdlib/runtime_probe.o test/selfhost/nostdlib_runtime_probe_amd64.S
	@ld -static -T src/runtime/linker/nostdlib.ld -o $(SELFHOST_DIR)/nostdlib/runtime_probe \
	  $(SELFHOST_DIR)/nostdlib/runtime.o \
	  $(SELFHOST_DIR)/nostdlib/runtime_probe.o
	@./misc/scripts/verify_true_selfhost.sh $(SELFHOST_DIR)/nostdlib/runtime_probe
	@test "$$($(SELFHOST_DIR)/nostdlib/runtime_probe)" = "nostdlib-runtime-ok"
	@echo "No-libc Linux/amd64 runtime check passed"

.PHONY: help bootstrap-stage0 bootstrap-convergence bootstrap-pure-s bootstrap-audit native-bootstrap direct-bootstrap native-bootstrap-install native-selfhost native-codegen-check bootstrap-subset-check bootstrap-slice1-check bootstrap-slice2-check bootstrap-slice3-check bootstrap-slice4-check bootstrap-slice5-check bootstrap-slice6-check pure-s-bootstrap-check bootstrap-source-closure selfhost selfhost-check true-selfhost-check selfhost-nostdlib selfhost-runtime-check verify-true-selfhost selfhost-lexer-check seed-frontend-lexer-check seed-frontend-parser-check selfhost-bin seed-tests seed-runtime-regression-bin seed-runtime-regression seed-network-tests sroutine-check seed-compiler-bin seed-c-abi-test test-quick test-full build-parallel selfhost-full

verify-true-selfhost:
	@./misc/scripts/verify_true_selfhost.sh "$(if $(SELFHOST_BIN),$(SELFHOST_BIN),./bin/s)"

help:
	@echo "  make run"
	@echo "  make build-x86_64"
	@echo "  make build-arm64"
	@echo "  make seed-tests"
	@echo "  make seed-runtime-regression"
	@echo "  make seed-network-tests"
	@echo "  make seed-c-abi-test"
	@echo "  make bootstrap-stage0       # Build the trusted C stage0 compiler"
	@echo "  make bootstrap-convergence  # Compatibility seed-hosted IR convergence"
	@echo "  make bootstrap-pure-s       # Run the pure-S bootstrap entrypoint"
	@echo "  make bootstrap-audit        # Report provenance and forbidden dependencies"
	@echo "  make native-bootstrap       # Build and compare pure-S stage1 -> stage2 -> stage3 binaries"
	@echo "  make direct-bootstrap       # Require S -> direct ELF stage2/stage3 convergence (no as/ld)"
	@echo "  make native-bootstrap-install # Install converged native stage2 as bin/s"
	@echo "  make native-selfhost          # Install the native bootstrap result as bin/s"
	@echo "  make native-codegen-check     # Verify S emits runnable ELF directly"
	@echo "  make bootstrap-subset-check # Enforce the frozen bootstrap declaration syntax"
	@echo "  make bootstrap-slice1-check # Build and exercise the first static pure-S compiler slice"
	@echo "  make bootstrap-slice2-check # Report the next native bootstrap frontier"
	@echo "  make bootstrap-slice3-check # Exercise native call/loop/string/array/multicall/copy"
	@echo "  make bootstrap-slice4-check # Exercise function control/logical/typed locals/large function"
	@echo "  make bootstrap-slice5-check # Exercise multi-call and argument passing frontier"
	@echo "  make bootstrap-slice6-check # Exercise string compare and branch-string frontier"
	@echo "  see doc/bootstrap.md         # Bootstrap ladder notes and slice rationale"
	@echo "  make pure-s-bootstrap-check # Run every implemented no-seed bootstrap frontier"
	@echo "  make bootstrap-source-closure # Resolve the pure-S compiler source closure"
	@echo "  make selfhost                # Install the native self-hosted compiler"
	@echo "  make seed-hosted-selfhost    # Install the seed-hosted compatibility path"
	@echo "  make selfhost-check"
	@echo "  make true-selfhost-check      # Reject a compiler that still links the C seed"
	@echo "  make selfhost-nostdlib        # Build without C library (experimental)"
	@echo "  make selfhost-runtime-check   # Verify the no-libc Linux/amd64 runtime"
	@echo "  make selfhost-lexer-check"
	@echo "  PARALLEL BUILDS:"
	@echo "  make test-quick               # Run quick tests only"
	@echo "  make test-full                # Run all tests in parallel"
	@echo "  make build-parallel           # Build all tools in parallel"
	@echo "  make selfhost-full            # Complete bootstrapping with parallel jobs"
	@echo "  CONFIGURATION:"
	@echo "  make PARALLEL_JOBS=8          # Override CPU count (default: nproc)"
	@echo "  override install dir: make INSTALL_BIN_DIR=/usr/local/bin SUDO=sudo"

test-quick: seed-tests
	@echo "✓ Quick tests passed"

test-full: seed-compiler-bin
	@echo "Running test suites with isolated runtime resources..."
	@$(MAKE) seed-tests
	@$(MAKE) seed-runtime-regression
	@echo "✓ All tests passed"

build-parallel:
	@echo "Building seed compiler, tests, and regression tests in parallel ($(PARALLEL_JOBS) jobs)..."
	@set -e; \
	$(MAKE) seed-compiler-bin & seed_pid=$$!; \
	$(MAKE) seed-tests & tests_pid=$$!; \
	$(MAKE) seed-runtime-regression-bin & regression_pid=$$!; \
	status=0; \
	wait $$seed_pid || status=$$?; \
	wait $$tests_pid || status=$$?; \
	wait $$regression_pid || status=$$?; \
	exit $$status
	@echo "✓ All builds completed"

selfhost-full: build-parallel selfhost selfhost-check
	@echo "✓ Full self-host bootstrapping completed"

selfhost-bin:
	@if [[ -z "$(COMPILER)" ]]; then \
		echo "error: no compiler found; set COMPILER=/app/s/bin/c_arm64_YYYYMMDDHHMMSS" >&2; \
		exit 1; \
	fi
	./scripts/selfhost_emit_bin.sh "$(COMPILER)" "$(OUT_BIN)" "$(OUT_IR)" "$(WORK_DIR)"
