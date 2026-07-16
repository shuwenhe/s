PREFIX ?= $(CURDIR)/.local
INSTALL_BIN_DIR ?= $(PREFIX)/bin
INSTALL_PROGRAM ?= install
SUDO ?=
SELFHOST_DIR ?= $(CURDIR)/.bootstrap/selfhost

run:
	@echo "Building and installing S compiler for $(shell uname -m)..."
	@set -e; \
	OUT_BIN=""; \
	case "$(shell uname -m)" in \
		x86_64) \
			if [ ! -f ./bin/build_s_x86_64.sh ]; then \
				echo "Missing builder: ./bin/build_s_x86_64.sh"; \
				exit 1; \
			fi; \
			OUT_BIN="$$(bash ./bin/build_s_x86_64.sh)"; \
			;; \
		aarch64|arm64) \
			if [ ! -f ./bin/build_s_arm64.sh ]; then \
				echo "Missing builder: ./bin/build_s_arm64.sh"; \
				exit 1; \
			fi; \
			OUT_BIN="$$(bash ./bin/build_s_arm64.sh)"; \
			;; \
		*) \
			echo "Unsupported architecture: $(shell uname -m)"; \
			exit 1; \
			;; \
	esac; \
	if [ ! -f "$$OUT_BIN" ]; then \
		echo "Build succeeded but output not found: $$OUT_BIN"; \
		exit 1; \
	fi; \
	mkdir -p "$(INSTALL_BIN_DIR)"; \
	echo "Installing $$OUT_BIN to $(INSTALL_BIN_DIR)/s..."; \
	$(SUDO) $(INSTALL_PROGRAM) -m 0755 "$$OUT_BIN" "$(INSTALL_BIN_DIR)/s"; \
	echo "S compiler installed successfully."

build-x86_64:
	@echo "Building S compiler for x86_64..."
	@bash ./bin/build_s_x86_64.sh

build-arm64:
	@echo "Building S compiler for ARM64..."
	@bash ./bin/build_s_arm64.sh

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
	  src/cmd/compile/seed/runtime/network_windows.c \
	  src/cmd/compile/seed/runtime/runtime.c

seed-runtime-regression: seed-runtime-regression-bin
	@./bin/seed_runtime_regression

seed-network-tests: seed-runtime-regression-bin
	@./bin/seed_runtime_regression --network-only

seed-compiler-bin:
	@mkdir -p ./bin
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
	  src/cmd/compile/seed/runtime/network_windows.c \
	  src/cmd/compile/seed/runtime/runtime.c

seed-c-abi-test: seed-compiler-bin
	@mkdir -p /tmp/s_seed_c_abi_test
	@./bin/s_seed tests/c_abi/add.s /tmp/s_seed_c_abi_test/add.ir
	@S_SOURCE_ROOT=$(CURDIR) ./bin/s_seed --emit-shared /tmp/s_seed_c_abi_test/add.ir /tmp/s_seed_c_abi_test/libs_add.$$(if [ "$$(uname -s)" = Darwin ]; then echo dylib; else echo so; fi)
	@gcc -std=c11 -Wall -Wextra -Werror -o /tmp/s_seed_c_abi_test/caller tests/c_abi/caller.c $$(if [ "$$(uname -s)" = Darwin ]; then echo; else echo -ldl; fi)
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
	@./bin/s_seed --dump-tokens tests/selfhost/lexer_fixture.s $(SELFHOST_DIR)/tokens.seed
	@$(SELFHOST_DIR)/s_lexer tests/selfhost/lexer_fixture.s $(SELFHOST_DIR)/tokens.s
	@cmp $(SELFHOST_DIR)/tokens.seed $(SELFHOST_DIR)/tokens.s
	@./bin/s_seed --dump-tokens tests/selfhost/lexer_unterminated_string.s $(SELFHOST_DIR)/unterminated-string.seed
	@$(SELFHOST_DIR)/s_lexer tests/selfhost/lexer_unterminated_string.s $(SELFHOST_DIR)/unterminated-string.s
	@cmp $(SELFHOST_DIR)/unterminated-string.seed $(SELFHOST_DIR)/unterminated-string.s
	@./bin/s_seed --dump-tokens tests/selfhost/lexer_unterminated_comment.s $(SELFHOST_DIR)/unterminated-comment.seed
	@$(SELFHOST_DIR)/s_lexer tests/selfhost/lexer_unterminated_comment.s $(SELFHOST_DIR)/unterminated-comment.s
	@cmp $(SELFHOST_DIR)/unterminated-comment.seed $(SELFHOST_DIR)/unterminated-comment.s
	@./bin/s_seed --dump-tokens tests/selfhost/lexer_illegal_char.s $(SELFHOST_DIR)/illegal-char.seed
	@$(SELFHOST_DIR)/s_lexer tests/selfhost/lexer_illegal_char.s $(SELFHOST_DIR)/illegal-char.s
	@cmp $(SELFHOST_DIR)/illegal-char.seed $(SELFHOST_DIR)/illegal-char.s
	@$(INSTALL_PROGRAM) -m 0755 $(SELFHOST_DIR)/s_lexer ./bin/s_lexer
	@echo "S lexer check passed: S token stream == seed token stream"

selfhost-check: selfhost selfhost-lexer-check
	@./bin/s tests/c_abi/add.s $(SELFHOST_DIR)/final-check.ir
	@S_LEXER_MODE=selfhost S_SELFHOST_LEXER=$(SELFHOST_DIR)/s_lexer ./bin/s tests/c_abi/add.s $(SELFHOST_DIR)/s-lexer-parser.ir
	@cmp $(SELFHOST_DIR)/final-check.ir $(SELFHOST_DIR)/s-lexer-parser.ir
	@cmp $(SELFHOST_DIR)/stage2.ir $(SELFHOST_DIR)/stage3.ir
	@echo "Self-host check passed: stage2 == stage3 and S Lexer -> Parser IR matches seed"

.PHONY: help selfhost selfhost-check selfhost-lexer-check selfhost-bin seed-tests seed-runtime-regression-bin seed-runtime-regression seed-network-tests seed-compiler-bin seed-c-abi-test

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
	@echo "  make selfhost-lexer-check"
	@echo "  override install dir: make INSTALL_BIN_DIR=/usr/local/bin SUDO=sudo"

selfhost-bin:
	@if [[ -z "$(COMPILER)" ]]; then \
		echo "error: no compiler found; set COMPILER=/app/s/bin/c_arm64_YYYYMMDDHHMMSS" >&2; \
		exit 1; \
	fi
	./scripts/selfhost_emit_bin.sh "$(COMPILER)" "$(OUT_BIN)" "$(OUT_IR)" "$(WORK_DIR)"
