PREFIX ?= $(HOME)/.local
INSTALL_BIN_DIR ?= $(PREFIX)/bin
INSTALL_PROGRAM ?= install
SUDO ?=
SELFHOST_DIR ?= $(CURDIR)/.bootstrap/selfhost
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

seed-compiler-bin:
	@mkdir -p ./bin
	@echo "Building seed compiler..."
	@gcc -std=c11 -Wall -Wextra -Werror \
	  -o ./bin/s_seed \
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

seed-c-abi-test: seed-compiler-bin
	@mkdir -p /tmp/s_seed_c_abi_test
	@./bin/s_seed test/c_abi/add.s /tmp/s_seed_c_abi_test/add.ir
	@S_SOURCE_ROOT=$(CURDIR) ./bin/s_seed --emit-shared /tmp/s_seed_c_abi_test/add.ir /tmp/s_seed_c_abi_test/libs_add.$$(if [ "$$(uname -s)" = Darwin ]; then echo dylib; else echo so; fi)
	@gcc -std=c11 -Wall -Wextra -Werror -o /tmp/s_seed_c_abi_test/caller test/c_abi/caller.c $$(if [ "$$(uname -s)" = Darwin ]; then echo; else echo -ldl; fi)
	@/tmp/s_seed_c_abi_test/caller /tmp/s_seed_c_abi_test/libs_add.$$(if [ "$$(uname -s)" = Darwin ]; then echo dylib; else echo so; fi)

selfhost: seed-compiler-bin
	@mkdir -p $(SELFHOST_DIR) ./bin
	@S_SOURCE_ROOT=$(CURDIR) ./bin/s_seed --bootstrap src/cmd/compile/main.s $(SELFHOST_DIR)
	@$(INSTALL_PROGRAM) -m 0755 $(SELFHOST_DIR)/stage2 ./bin/s
	@echo "Installed self-hosted S compiler: ./bin/s"

selfhost-lexer-check: seed-compiler-bin
	@mkdir -p $(SELFHOST_DIR) ./bin
	@./bin/s_seed src/cmd/compile/selfhost/lexer.s $(SELFHOST_DIR)/lexer.ir
	@S_SOURCE_ROOT=$(CURDIR) ./bin/s_seed --emit-bin $(SELFHOST_DIR)/lexer.ir $(SELFHOST_DIR)/s_lexer
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
	@echo "S lexer check passed: S token stream == seed token stream"

selfhost-check: selfhost selfhost-lexer-check
	@./bin/s test/c_abi/add.s $(SELFHOST_DIR)/final-check.ir
	@S_LEXER_MODE=selfhost S_SELFHOST_LEXER=$(SELFHOST_DIR)/s_lexer ./bin/s test/c_abi/add.s $(SELFHOST_DIR)/s-lexer-parser.ir
	@cmp $(SELFHOST_DIR)/final-check.ir $(SELFHOST_DIR)/s-lexer-parser.ir
	@cmp $(SELFHOST_DIR)/stage2.ir $(SELFHOST_DIR)/stage3.ir
	@echo "Seed-hosted bootstrap check passed: stage2 == stage3 and S Lexer -> Parser IR matches seed"

true-selfhost-check: selfhost-check
	@./misc/scripts/verify_true_selfhost.sh ./bin/s
	@echo "True self-host check passed: ./bin/s does not link the C seed compiler"

# A producer for bin/s_nostdlib must be added before this target can pass.  Keep
# this target fail-closed: an absent artifact must never be reported as a
# successful no-libc bootstrap.
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

.PHONY: help selfhost selfhost-check true-selfhost-check selfhost-nostdlib selfhost-runtime-check verify-true-selfhost selfhost-lexer-check selfhost-bin seed-tests seed-runtime-regression-bin seed-runtime-regression seed-network-tests seed-compiler-bin seed-c-abi-test test-quick test-full build-parallel selfhost-full

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
	@echo "  make selfhost"
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
