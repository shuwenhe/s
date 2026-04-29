run:
	@echo "Building and installing S compiler for $(shell uname -m)..."
	@set -e; \
	OUT_BIN=""; \
	case "$(shell uname -m)" in \
		x86_64) \
			if [ ! -x ./bin/build_s_x86_64.sh ]; then \
				echo "Missing builder: ./bin/build_s_x86_64.sh"; \
				exit 1; \
			fi; \
			OUT_BIN="$$(./bin/build_s_x86_64.sh)"; \
			;; \
		aarch64|arm64) \
			OUT_BIN="$$(./bin/build_s_arm64.sh)"; \
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
	echo "Installing $$OUT_BIN to /usr/local/bin/s..."; \
	install -m 0755 "$$OUT_BIN" /usr/local/bin/s; \
	echo "S compiler installed successfully."

build-x86_64:
	@echo "Building S compiler for x86_64..."
	@./bin/build_s_x86_64.sh

build-arm64:
	@echo "Building S compiler for ARM64..."
	@./bin/build_s_arm64.sh

.PHONY: help selfhost-bin

help:
	@echo "  make run"

selfhost-bin:
	@if [[ -z "$(COMPILER)" ]]; then \
		echo "error: no compiler found; set COMPILER=/app/s/bin/c_arm64_YYYYMMDDHHMMSS" >&2; \
		exit 1; \
	fi
	./scripts/selfhost_emit_bin.sh "$(COMPILER)" "$(OUT_BIN)" "$(OUT_IR)" "$(WORK_DIR)"
