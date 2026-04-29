run:
	$(MAKE) build-arm64
	$(MAKE) selfhost-bin
	install -m 755 $$(ls -1t bin/s_arm64_* 2>/dev/null | head -n 1) /usr/local/bin/s
	@echo "Installed S compiler to /usr/local/bin/s"
SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help

COMPILER ?= $(shell ls -1t bin/c_arm64_* 2>/dev/null | head -n 1)
OUT_BIN ?= $(shell TZ=Asia/Shanghai date +"bin/s_arm64_%Y%m%d%H%M%S")
OUT_IR ?= /tmp/s_ir_selfhost_main.ir
WORK_DIR ?= /tmp/s_ir_selfhost_work

.PHONY: help build-arm64 selfhost-bin

help:
	@echo "Available targets:"
	@grep -E '^[a-zA-Z0-9_-]+:' Makefile | grep -vE '^\.' | awk '{print "  make", $$1}' | sed 's/://g'
	@echo "  make build-arm64                    # build a new arm64 C-seed compiler (c_arm64_*)"
	@echo "  make selfhost-bin [COMPILER=...]    # IR -> executable compiler -> compile main.s"
	@echo ""
	@echo "Variables for selfhost-bin:"
	@echo "  COMPILER=$(COMPILER)"
	@echo "  OUT_BIN=$(OUT_BIN)"
	@echo "  OUT_IR=$(OUT_IR)"
	@echo "  WORK_DIR=$(WORK_DIR)"

build-arm64:
	./bin/build_s_arm64.sh

selfhost-bin:
	@if [[ -z "$(COMPILER)" ]]; then \
		echo "error: no compiler found; set COMPILER=/app/s/bin/c_arm64_YYYYMMDDHHMMSS" >&2; \
		exit 1; \
	fi
	./scripts/selfhost_emit_bin.sh "$(COMPILER)" "$(OUT_BIN)" "$(OUT_IR)" "$(WORK_DIR)"
